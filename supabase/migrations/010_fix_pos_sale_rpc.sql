-- Fix for process_pos_sale RPC function signature
-- Adds default values to optional parameters to prevent "function not found" errors
-- when certain fields (like customerId) are missing or undefined.

DROP FUNCTION IF EXISTS public.process_pos_sale(JSONB, UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB, TEXT);

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
  p_customer_name TEXT DEFAULT 'Walk-in'
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
BEGIN
  -- 1. Generate Invoice Number
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 10000)::text, 4, '0');

  -- 2. Calculate Sub-total
  v_sub_total := p_total_amount + p_discount_amount;

  -- 3. Insert Sale
  INSERT INTO public.sales (
    invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, created_at
  )
  VALUES (
    v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed', NOW()
  )
  RETURNING id INTO v_sale_id;

  -- 4. Insert Sale Items and Update Stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.sale_items (sale_id, product_id, product_name, quantity, unit_price, total_price)
    VALUES (
      v_sale_id, 
      (v_item->>'product_id')::UUID, 
      v_item->>'product_name', 
      (v_item->>'quantity')::INTEGER, 
      (v_item->>'unit_price')::NUMERIC,
      (v_item->>'total_price')::NUMERIC
    );

    -- Update Stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'product_id')::UUID;
  END LOOP;

  -- 5. Handle Credit Update
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

  -- 6. Audit Log (Optional)
  -- PERFORM log_stock_movement(...) can be added here if needed

  RETURN jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice_number,
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql;
