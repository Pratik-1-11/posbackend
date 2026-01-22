-- ============================================================================
-- Fix: RPC Signature Mismatch
-- The database function still requires p_tenant_id, but backend code removed it for security.
-- We must update the database function to match.
-- ============================================================================

-- 1. Drop the old function (We must do this because argument list is changing)
-- Depending on exact signature in DB, we'll try to drop the most likely candidates
DROP FUNCTION IF EXISTS public.process_pos_sale(jsonb, uuid, uuid, uuid, numeric, numeric, uuid, numeric, numeric, text, jsonb, text);
DROP FUNCTION IF EXISTS public.process_pos_sale(jsonb, uuid, uuid, uuid, numeric, numeric, numeric, numeric, text, jsonb, text, text);
-- Also try dropping simply by name (Postgres might complain if overloaded, but usually fine here)
DROP FUNCTION IF EXISTS public.process_pos_sale;

-- 2. Create the new, Secure version (NO p_tenant_id param)
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
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_tenant_id UUID;
  v_prod_tenant UUID;
  v_stock_qty INTEGER;
BEGIN
  -- 1. Security Context
  v_tenant_id := public.get_user_tenant_id();
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Tenant not found'; END IF;

  -- 2. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.sales WHERE idempotency_key = p_idempotency_key AND tenant_id = v_tenant_id) THEN
      RETURN (SELECT jsonb_build_object('id', id, 'invoice_number', invoice_number, 'status', 'duplicate') 
              FROM public.sales WHERE idempotency_key = p_idempotency_key);
    END IF;
  END IF;

  -- 3. Generation
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 1000000)::text, 6, '0');
  v_sub_total := p_total_amount + p_discount_amount;

  -- 4. Insert Sale
  INSERT INTO public.sales (
    tenant_id,
    invoice_number,
    customer_id,
    cashier_id,
    branch_id,
    sub_total,
    discount_amount,
    taxable_amount,
    vat_amount,
    total_amount,
    payment_method,
    payment_details,
    customer_name,
    status,
    idempotency_key
  ) VALUES (
    v_tenant_id,
    v_invoice_number,
    p_customer_id,
    p_cashier_id,
    p_branch_id,
    v_sub_total,
    p_discount_amount,
    p_taxable_amount,
    p_vat_amount,
    p_total_amount,
    p_payment_method,
    p_payment_details,
    p_customer_name,
    'completed',
    p_idempotency_key
  )
  RETURNING id INTO v_sale_id;

  -- 5. Process Items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- Verify product belongs to tenant (Explicit Check)
    SELECT tenant_id, stock_quantity INTO v_prod_tenant, v_stock_qty 
    FROM public.products 
    WHERE id = (v_item->>'productId')::uuid;

    IF v_prod_tenant IS NULL OR v_prod_tenant != v_tenant_id THEN
      RAISE EXCEPTION 'Product not found or access denied: %', (v_item->>'productId');
    END IF;
    
    -- Stock check
    IF v_stock_qty < (v_item->>'quantity')::integer THEN
       RAISE EXCEPTION 'Insufficient stock for product: %', (v_item->>'productId');
    END IF;

    -- Insert Item
    INSERT INTO public.sale_items (
      tenant_id,
      sale_id,
      product_id,
      product_name,
      quantity,
      unit_price,
      total_price
    ) VALUES (
      v_tenant_id,
      v_sale_id,
      (v_item->>'productId')::uuid,
      v_item->>'name',
      (v_item->>'quantity')::integer,
      (v_item->>'price')::numeric,
      (v_item->>'quantity')::integer * (v_item->>'price')::numeric
    );

    -- Update Stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::integer
    WHERE id = (v_item->>'productId')::uuid;
  END LOOP;

  -- 6. Update Customer Credit (Atomic)
  IF p_customer_id IS NOT NULL AND p_payment_method = 'credit' THEN
    PERFORM public.add_customer_transaction(
      p_customer_id,
      'sale',
      p_total_amount,
      'Credit Sale ' || v_invoice_number,
      v_sale_id
    );
  END IF;

  RETURN jsonb_build_object(
    'sale', (SELECT row_to_json(s) FROM public.sales s WHERE id = v_sale_id),
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
