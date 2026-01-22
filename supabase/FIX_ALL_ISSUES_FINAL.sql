-- ============================================================================
-- MASTER FIX SCRIPT - Run this to resolve ALL 500 errors and Security Issues
-- Combines: Audit Log Fix, Credit Limit Fix, Secure RPC Fix, Constraints, and Data Backfill
-- ============================================================================

-- ============================================================================
-- 1. FIX AUDIT LOGS (Fixes 500 Error on Create Customer/Sale)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.audit_logs ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'entity_type') THEN
        ALTER TABLE public.audit_logs ADD COLUMN entity_type TEXT DEFAULT 'system';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'entity_id') THEN
        ALTER TABLE public.audit_logs ADD COLUMN entity_id UUID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'actor_id') THEN
        ALTER TABLE public.audit_logs ADD COLUMN actor_id UUID REFERENCES auth.users(id);
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_audit_tenant_date ON public.audit_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON public.audit_logs(entity_type, entity_id);

-- ============================================================================
-- 2. FIX CUSTOMERS TABLE (Fixes 500 Error on Create Customer)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'customers' AND column_name = 'credit_limit') THEN
        ALTER TABLE public.customers ADD COLUMN credit_limit NUMERIC(10, 2) DEFAULT 0 CHECK (credit_limit >= 0);
    END IF;
END $$;

-- 2.1 BACKFILL DEFAULT CREDIT LIMITS (Unblocks existing customers)
UPDATE public.customers 
SET credit_limit = 10000 
WHERE credit_limit IS NULL OR credit_limit = 0;

-- ============================================================================
-- 2.5. ENSURE HELPER FUNCTION EXISTS (Required for Credit Sales)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.add_customer_transaction(
  p_customer_id UUID,
  p_type TEXT,
  p_amount NUMERIC,
  p_description TEXT,
  p_reference_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS UUID AS $$
DECLARE
  v_transaction_id UUID;
BEGIN
  -- Insert Transaction
  INSERT INTO public.customer_transactions (customer_id, type, amount, description, reference_id, performed_by)
  VALUES (p_customer_id, p_type, p_amount, p_description, p_reference_id, p_user_id)
  RETURNING id INTO v_transaction_id;

  -- Update Balance
  IF p_type IN ('sale', 'opening_balance') THEN
    UPDATE public.customers SET total_credit = total_credit + p_amount WHERE id = p_customer_id;
  ELSIF p_type IN ('payment', 'return') THEN
    UPDATE public.customers SET total_credit = total_credit - p_amount WHERE id = p_customer_id;
  ELSIF p_type = 'adjustment' THEN
    UPDATE public.customers SET total_credit = total_credit + p_amount WHERE id = p_customer_id;
  END IF;

  RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. FIX RPC SIGNATURE & SECURITY (Fixes 500 Error on Create Order)
-- ============================================================================
DROP FUNCTION IF EXISTS public.process_pos_sale(jsonb, uuid, uuid, uuid, numeric, numeric, numeric, numeric, text, jsonb, text, text);
DROP FUNCTION IF EXISTS public.process_pos_sale(jsonb, uuid, uuid, uuid, numeric, numeric, uuid, numeric, numeric, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.process_pos_sale(
  p_items JSONB,
  p_customer_id UUID DEFAULT NULL,
  p_cashier_id UUID DEFAULT NULL,
  p_branch_id UUID DEFAULT NULL,
  p_discount_amount NUMERIC DEFAULT 0,
  p_taxable_amount NUMERIC DEFAULT 0,
  p_vat_amount NUMERIC DEFAULT 0,
  p_total_amount NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_payment_details JSONB DEFAULT '{}'::jsonb,
  p_customer_name TEXT DEFAULT 'Walk-in',
  p_idempotency_key TEXT DEFAULT NULL,
  p_tenant_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_active_tenant_id UUID;
  v_jwt_role TEXT;
  v_prod_tenant UUID;
  v_stock_qty INTEGER;
  v_sub_total NUMERIC;
  v_credit_amount NUMERIC := 0;
  v_current_credit NUMERIC;
  v_credit_limit NUMERIC;
BEGIN
  -- 1. Security & Tenant Resolution
  -- Robustly check for Service Role
  v_jwt_role := auth.jwt() ->> 'role';
  
  IF v_jwt_role = 'service_role' THEN
    -- Backend API: Trust the passed tenant_id
    IF p_tenant_id IS NULL THEN RAISE EXCEPTION 'Service Role must provide p_tenant_id'; END IF;
    v_active_tenant_id := p_tenant_id;
  ELSE
    -- Regular User: FORCE tenant_id from their token
    v_active_tenant_id := public.get_user_tenant_id();
    IF v_active_tenant_id IS NULL THEN 
       RAISE EXCEPTION 'Unauthorized: Tenant not found in user context. Detected Role: %', COALESCE(v_jwt_role, 'none'); 
    END IF;
  END IF;

  -- 2. Validate Credit Rules (Before creating sale)
  -- Determine Credit Amount based on payment method
  IF p_payment_method = 'credit' THEN
    v_credit_amount := p_total_amount;
  ELSIF p_payment_method = 'mixed' THEN
    -- Build robustness: handle string or number input in JSON
    v_credit_amount := COALESCE((p_payment_details->>'credit')::numeric, 0);
  END IF;

  -- Check Limits if this is a credit transaction
  IF v_credit_amount > 0 THEN
      IF p_customer_id IS NULL THEN
          RAISE EXCEPTION 'Customer is required for credit sales.';
      END IF;

      SELECT total_credit, credit_limit INTO v_current_credit, v_credit_limit 
      FROM public.customers WHERE id = p_customer_id;

      IF v_credit_limit IS NULL OR v_credit_limit <= 0 THEN
         RAISE EXCEPTION 'Customer does not have a valid credit limit set.';
      END IF;

      IF (v_current_credit + v_credit_amount) > v_credit_limit THEN
         RAISE EXCEPTION 'Credit limit exceeded. Limit: %, Current Balance: %, Attempted: %', v_credit_limit, v_current_credit, v_credit_amount;
      END IF;
  END IF;

  -- 3. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.sales WHERE idempotency_key = p_idempotency_key AND tenant_id = v_active_tenant_id) THEN
      RETURN (SELECT jsonb_build_object('id', id, 'invoice_number', invoice_number, 'status', 'duplicate') FROM public.sales WHERE idempotency_key = p_idempotency_key);
    END IF;
  END IF;

  -- 4. Generation
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 1000000)::text, 6, '0');
  v_sub_total := p_total_amount + p_discount_amount;

  -- 5. Insert Sale
  INSERT INTO public.sales (tenant_id, invoice_number, customer_id, cashier_id, branch_id, sub_total, discount_amount, taxable_amount, vat_amount, total_amount, payment_method, payment_details, customer_name, status, idempotency_key) 
  VALUES (v_active_tenant_id, v_invoice_number, p_customer_id, p_cashier_id, p_branch_id, v_sub_total, p_discount_amount, p_taxable_amount, p_vat_amount, p_total_amount, p_payment_method, p_payment_details, p_customer_name, 'completed', p_idempotency_key)
  RETURNING id INTO v_sale_id;

  -- 6. Process Items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT tenant_id, stock_quantity INTO v_prod_tenant, v_stock_qty FROM public.products WHERE id = (v_item->>'productId')::uuid;
    IF v_prod_tenant IS NULL OR v_prod_tenant != v_active_tenant_id THEN RAISE EXCEPTION 'Product not found or access denied: %', (v_item->>'productId'); END IF;
    IF v_stock_qty < (v_item->>'quantity')::integer THEN RAISE EXCEPTION 'Insufficient stock for product: %', (v_item->>'productId'); END IF;

    INSERT INTO public.sale_items (tenant_id, sale_id, product_id, product_name, quantity, unit_price, total_price) 
    VALUES (v_active_tenant_id, v_sale_id, (v_item->>'productId')::uuid, v_item->>'name', (v_item->>'quantity')::integer, (v_item->>'price')::numeric, (v_item->>'quantity')::integer * (v_item->>'price')::numeric);

    UPDATE public.products SET stock_quantity = stock_quantity - (v_item->>'quantity')::integer WHERE id = (v_item->>'productId')::uuid;
  END LOOP;

  -- 7. Update Customer Credit (Using calculated amount)
  IF p_customer_id IS NOT NULL AND v_credit_amount > 0 THEN
    -- Use v_credit_amount instead of p_total_amount because mixed payments might only be partial credit
    PERFORM public.add_customer_transaction(p_customer_id, 'sale', v_credit_amount, 'Credit Sale ' || v_invoice_number, v_sale_id, auth.uid());
  END IF;

  RETURN jsonb_build_object('sale', (SELECT row_to_json(s) FROM public.sales s WHERE id = v_sale_id), 'status', 'success');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 4. APPLY SECURITY CONSTRAINTS (Fixes Negative Stock/Prices)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'stock_non_negative') THEN
        ALTER TABLE public.products ADD CONSTRAINT stock_non_negative CHECK (stock_quantity >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'selling_price_non_negative') THEN
        ALTER TABLE public.products ADD CONSTRAINT selling_price_non_negative CHECK (selling_price >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'credit_non_negative') THEN
        ALTER TABLE public.customers ADD CONSTRAINT credit_non_negative CHECK (total_credit >= 0);
    END IF;
END $$;
