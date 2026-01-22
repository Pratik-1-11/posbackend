-- Secure POS Sale Processing 
-- Version 2.0: Atomic, Secure, and Idempotent

-- 1. DROP ALL VERSIONS OF THE FUNCTION (Clean Slate)
DO $$
DECLARE
    func_record record;
BEGIN
    FOR func_record IN (
        SELECT oid::regprocedure as signature
        FROM pg_proc 
        WHERE proname = 'process_pos_sale' 
        AND pronamespace = 'public'::regnamespace
    )
    LOOP
        EXECUTE 'DROP FUNCTION ' || func_record.signature;
    END LOOP;
END $$;

-- 2. ENSURE INFRASTRUCTURE
CREATE SEQUENCE IF NOT EXISTS public.sales_invoice_seq START 1000;

-- 3. CREATE FINAL SECURE VERSION
CREATE OR REPLACE FUNCTION public.process_pos_sale(
  p_items JSONB,
  p_tenant_id UUID,        
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
  p_idempotency_key TEXT DEFAULT NULL 
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_prod_tenant UUID;
BEGIN
  -- 1. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.sales WHERE idempotency_key = p_idempotency_key) THEN
      RETURN (SELECT jsonb_build_object(
        'id', id, 
        'invoice_number', invoice_number, 
        'status', 'duplicate'
      ) FROM public.sales WHERE idempotency_key = p_idempotency_key);
    END IF;
  END IF;

  -- 2. Validate Tenant
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant ID is required for sale processing';
  END IF;

  -- 3. Generate Invoice Number
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(nextval('public.sales_invoice_seq')::text, 6, '0');
  v_sub_total := p_total_amount + p_discount_amount;

  -- 4. Insert Sale
  INSERT INTO public.sales (
    tenant_id, invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, idempotency_key
  )
  VALUES (
    p_tenant_id, v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed', p_idempotency_key
  )
  RETURNING id INTO v_sale_id;

  -- 5. Process Items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- Strict Ownership Check
    SELECT tenant_id INTO v_prod_tenant FROM public.products WHERE id = (v_item->>'product_id')::UUID;
    
    IF v_prod_tenant IS NULL OR v_prod_tenant != p_tenant_id THEN
      RAISE EXCEPTION 'Security Error: Product % does not belong to your store', (v_item->>'product_name');
    END IF;

    -- Insert Item
    INSERT INTO public.sale_items (sale_id, product_id, product_name, quantity, unit_price, total_price, tenant_id)
    VALUES (v_sale_id, (v_item->>'product_id')::UUID, v_item->>'product_name', (v_item->>'quantity')::INTEGER, (v_item->>'unit_price')::NUMERIC, (v_item->>'total_price')::NUMERIC, p_tenant_id);

    -- Update Stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER,
        updated_at = NOW()
    WHERE id = (v_item->>'product_id')::UUID;
  END LOOP;

  -- 6. Customer Credit
  IF p_payment_method = 'credit' OR (p_payment_method = 'mixed' AND p_payment_details ? 'credit') THEN
     v_credit_amount := CASE WHEN p_payment_method = 'credit' THEN p_total_amount ELSE (p_payment_details->>'credit')::NUMERIC END;
     PERFORM add_customer_transaction(p_customer_id, 'sale', v_credit_amount, 'Sale: ' || v_invoice_number, v_sale_id, p_cashier_id);
  END IF;

  RETURN jsonb_build_object('id', v_sale_id, 'invoice_number', v_invoice_number, 'status', 'success');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
