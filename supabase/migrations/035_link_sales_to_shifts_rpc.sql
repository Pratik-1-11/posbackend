-- Migration: 035_link_sales_to_shifts_rpc.sql
-- Purpose: Automatically link sales to active shift sessions and enforce shift requirement

CREATE OR REPLACE FUNCTION public.process_pos_sale(
  p_items JSONB,
  p_customer_id UUID,
  p_cashier_id UUID,
  p_branch_id UUID,
  p_discount_amount NUMERIC,
  p_taxable_amount NUMERIC,
  p_vat_amount NUMERIC,
  p_total_amount NUMERIC,
  p_payment_method TEXT,
  p_payment_details JSONB,
  p_customer_name TEXT DEFAULT 'Walk-in',
  p_idempotency_key UUID DEFAULT NULL,
  p_tenant_id UUID DEFAULT NULL,
  p_customer_pan TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_shift_id UUID;
BEGIN
  -- 0. Shift Enforcement: Find active shift for this cashier
  SELECT id INTO v_shift_id
  FROM public.shift_sessions
  WHERE cashier_id = p_cashier_id 
    AND tenant_id = p_tenant_id
    AND status = 'open'
  LIMIT 1;

  IF v_shift_id IS NULL THEN
    RAISE EXCEPTION 'A shift session must be open before processing sales. Please start your shift.';
  END IF;

  -- 1. Idempotency Check (if key provided)
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, invoice_number INTO v_sale_id, v_invoice_number
    FROM public.sales
    WHERE idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'status', 'success',
        'id', v_sale_id,
        'invoice_number', v_invoice_number,
        'is_duplicate', true,
        'message', 'Duplicate request handled'
      );
    END IF;
  END IF;

  -- 2. Generate Invoice Number (Unique per tenant)
  -- Real implementation might use a sequence or more robust numbering
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 100000)::text, 5, '0');

  -- 3. Calculate Sub-total
  v_sub_total := p_total_amount + p_discount_amount;

  -- 4. Insert Sale (linked to shift_id)
  INSERT INTO public.sales (
    tenant_id, invoice_number, cashier_id, branch_id, customer_id, customer_name,
    customer_pan, payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, shift_id, idempotency_key, created_at
  )
  VALUES (
    p_tenant_id, v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_customer_pan, p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed', v_shift_id, p_idempotency_key, NOW()
  )
  RETURNING id INTO v_sale_id;

  -- 5. Insert Sale Items and Update Stock
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.sale_items (sale_id, product_id, product_name, quantity, unit_price, total_price)
    VALUES (
      v_sale_id, 
      (v_item->>'productId')::UUID, -- Handling camelCase from JS
      (v_item->>'name'), 
      (v_item->>'quantity')::INTEGER, 
      (v_item->>'price')::NUMERIC,
      (v_item->>'total')::NUMERIC
    );

    -- Update Stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'productId')::UUID AND tenant_id = p_tenant_id;
  END LOOP;

  -- 6. Handle Credit Update
  IF p_payment_method = 'credit' THEN
    v_credit_amount := p_total_amount;
  ELSIF p_payment_method = 'mixed' THEN
    v_credit_amount := COALESCE((p_payment_details->>'credit')::NUMERIC, 0);
  END IF;

  IF v_credit_amount > 0 AND p_customer_id IS NOT NULL THEN
    -- Update customer credit balance and log transaction
    INSERT INTO public.customer_transactions (
      tenant_id, customer_id, transaction_type, amount, description, reference_id, cashier_id
    ) VALUES (
      p_tenant_id, p_customer_id, 'sale', v_credit_amount, 
      'POS Sale: ' || v_invoice_number, v_sale_id, p_cashier_id
    );

    UPDATE public.customers
    SET total_credit = total_credit + v_credit_amount,
        updated_at = NOW()
    WHERE id = p_customer_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice_number,
    'total_amount', p_total_amount,
    'payment_method', p_payment_method,
    'shift_id', v_shift_id,
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
