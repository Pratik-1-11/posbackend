-- Migration: Advanced Credit Payment System and Sales Atomicity
-- Created: 2025-12-31

-- 1. Update Sales Table to support mixed payments
ALTER TABLE public.sales 
ADD COLUMN IF NOT EXISTS payment_details JSONB DEFAULT '{}'::jsonb;

-- 2. Ensure payment_method check constraint allows 'mixed'
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_payment_method_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_payment_method_check 
  CHECK (payment_method IN ('cash', 'card', 'qr', 'mixed', 'credit'));

-- 3. Create missing decrement_stock if it's missing (though our new function will handle it)
CREATE OR REPLACE FUNCTION decrement_stock(p_product_id UUID, p_quantity INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.products 
  SET stock_quantity = stock_quantity - p_quantity
  WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql;

-- 4. ATOMIC POS SALE FUNCTION
-- This ensures that sale, items, stock, and credit are all updated or all fail.
CREATE OR REPLACE FUNCTION process_pos_sale(
  p_items JSONB, -- Array of {product_id, product_name, quantity, unit_price, total_price}
  p_customer_id UUID,
  p_cashier_id UUID,
  p_branch_id UUID,
  p_discount_amount NUMERIC,
  p_taxable_amount NUMERIC,
  p_vat_amount NUMERIC,
  p_total_amount NUMERIC,
  p_payment_method TEXT, -- 'cash', 'card', 'qr', 'credit', 'mixed'
  p_payment_details JSONB, -- Breakdown: {"cash": 100, "credit": 200, ...}
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

  -- 2. Calculate Sub-total from items just to double check
  v_sub_total := p_total_amount + p_discount_amount;

  -- 3. Insert Sale
  INSERT INTO public.sales (
    invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status
  )
  VALUES (
    v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed'
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
    -- Extract credit amount from details if it exists
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
      'Partial/Full Credit Sale: ' || v_invoice_number,
      v_sale_id,
      p_cashier_id
    );
  END IF;

  RETURN jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice_number,
    'total_amount', p_total_amount,
    'payment_method', p_payment_method,
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql;
