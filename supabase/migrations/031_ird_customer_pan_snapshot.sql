-- Migration: 031_ird_customer_pan_snapshot.sql
-- Description: Add customer_pan to sales table for snapshotting and walk-in support

-- 1. Add customer_pan column to sales table
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS customer_pan TEXT;

-- 2. Update IRD Sales Book View to prefer snapshot PAN
DROP VIEW IF EXISTS public.ird_sales_book;

CREATE OR REPLACE VIEW public.ird_sales_book AS
SELECT 
    s.created_at::DATE as date,
    s.invoice_number,
    COALESCE(s.invoice_type, 'tax-invoice') as invoice_type,
    COALESCE(s.customer_name, 'Walk-in') as customer_name,
    COALESCE(s.customer_pan, c.pan_number, 'N/A') as customer_pan, -- Prefer snapshot, then profile, then N/A
    s.taxable_amount,
    s.vat_amount,
    (s.total_amount - s.taxable_amount - s.vat_amount) as non_taxable_amount,
    s.total_amount,
    COALESCE(s.payment_method, 'cash') as payment_method,
    COALESCE(p.full_name, 'System') as cashier_name,
    s.tenant_id,
    s.status
FROM public.sales s
LEFT JOIN public.customers c ON s.customer_id = c.id
LEFT JOIN public.profiles p ON s.cashier_id = p.id

UNION ALL

-- Include Returns as Credit Notes
SELECT 
    r.created_at::DATE as date,
    'CN-' || s.invoice_number as invoice_number,
    'credit-note' as invoice_type,
    COALESCE(s.customer_name, 'Walk-in') as customer_name,
    COALESCE(s.customer_pan, c.pan_number, 'N/A') as customer_pan,
    -(r.total_refund_amount / 1.13) as taxable_amount,
    -(r.total_refund_amount - (r.total_refund_amount / 1.13)) as vat_amount,
    0 as non_taxable_amount,
    -r.total_refund_amount as total_amount,
    'refund' as payment_method,
    COALESCE(p.full_name, 'System') as cashier_name,
    r.tenant_id,
    'completed' as status
FROM public.returns r
JOIN public.sales s ON r.sale_id = s.id
LEFT JOIN public.customers c ON s.customer_id = c.id
LEFT JOIN public.profiles p ON r.cashier_id = p.id;

-- 3. Update process_pos_sale RPC to accept and store customer_pan
-- Drop strict signatures to ensure clean replace
DROP FUNCTION IF EXISTS public.process_pos_sale(JSONB, UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB, TEXT, TEXT, UUID);

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
  p_tenant_id UUID DEFAULT NULL,
  p_customer_pan TEXT DEFAULT NULL -- New Parameter
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_resolved_tenant_id UUID;
BEGIN
  -- 1. Resolve Tenant ID
  v_resolved_tenant_id := COALESCE(p_tenant_id, public.get_user_tenant_id());
  
  IF v_resolved_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant identification failed';
  END IF;

  -- 2. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, invoice_number INTO v_sale_id, v_invoice_number
    FROM public.sales 
    WHERE idempotency_key = p_idempotency_key AND tenant_id = v_resolved_tenant_id;
    
    IF v_sale_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'id', v_sale_id,
        'invoice_number', v_invoice_number,
        'status', 'duplicate',
        'message', 'Duplicate request handled'
      );
    END IF;
  END IF;

  -- 3. Generate Invoice Number
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(nextval('sale_invoice_seq')::text, 6, '0');

  -- 4. Calculate Sub-total
  v_sub_total := p_total_amount + p_discount_amount;

  -- 5. Insert Sale
  INSERT INTO public.sales (
    tenant_id, invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, idempotency_key, customer_pan
  )
  VALUES (
    v_resolved_tenant_id, v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed', p_idempotency_key, p_customer_pan
  )
  RETURNING id INTO v_sale_id;

  -- 6. Insert Sale Items and Update Stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.sale_items (tenant_id, sale_id, product_id, product_name, quantity, unit_price, total_price)
    VALUES (
      v_resolved_tenant_id,
      v_sale_id, 
      (v_item->>'productId')::UUID, 
      v_item->>'name', 
      (v_item->>'quantity')::INTEGER, 
      (v_item->>'price')::NUMERIC,
      (v_item->>'total')::NUMERIC
    );

    -- Update Stock (Scoped by tenant)
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'productId')::UUID AND tenant_id = v_resolved_tenant_id;
  END LOOP;

  -- 7. Handle Credit Update
  IF p_payment_method = 'credit' THEN
    v_credit_amount := p_total_amount;
  ELSIF p_payment_method = 'mixed' THEN
    IF p_payment_details ? 'credit' THEN
      v_credit_amount := (p_payment_details->>'credit')::NUMERIC;
    END IF;
  END IF;

  IF v_credit_amount > 0 THEN
    IF p_customer_id IS NULL THEN
      RAISE EXCEPTION 'Customer ID is required for credit payments';
    END IF;
    
    PERFORM add_customer_transaction(
      p_customer_id,
      'sale',
      v_credit_amount,
      'POS Sale: ' || v_invoice_number,
      v_sale_id,
      p_cashier_id
    );
  END IF;

  RETURN jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice_number,
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
