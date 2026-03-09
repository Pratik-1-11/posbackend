-- Migration: 051_enhance_pos_rpc_for_splits.sql
-- Description: Update process_pos_sale RPC to handle multi-method split payments

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
  p_customer_pan TEXT DEFAULT NULL,
  p_payment_splits JSONB DEFAULT NULL -- New Parameter
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_split JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_shift_id UUID;
  v_je_id UUID;
  
  -- Account variables for accounting hooks
  v_acct_cash UUID;
  v_acct_ar UUID;
  v_acct_sales UUID;
  v_acct_discount UUID;
  v_acct_vat UUID;

BEGIN
  -- 0. Shift Enforcement
  SELECT id INTO v_shift_id
  FROM public.shift_sessions
  WHERE cashier_id = p_cashier_id 
    AND tenant_id = p_tenant_id
    AND status = 'open'
  LIMIT 1;

  IF v_shift_id IS NULL THEN
    RAISE EXCEPTION 'A shift session must be open before processing sales.';
  END IF;

  -- 1. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id, invoice_number INTO v_sale_id, v_invoice_number
    FROM public.sales
    WHERE idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN jsonb_build_object('status', 'success', 'id', v_sale_id, 'invoice_number', v_invoice_number, 'is_duplicate', true);
    END IF;
  END IF;

  -- 2. Generate Invoice Number
  v_invoice_number := public.get_next_invoice_number(p_tenant_id, p_branch_id);

  -- 3. Calculate Sub-total
  v_sub_total := p_total_amount + p_discount_amount - p_vat_amount;

  -- 4. Insert Sale
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

  -- 5. Insert Sale Items & Update Inventory
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.sale_items (
        sale_id, product_id, product_name, quantity, unit_price, total_price,
        original_unit_price, override_reason, authorized_by, batch_id
    )
    VALUES (
      v_sale_id, 
      (v_item->>'productId')::UUID, 
      (v_item->>'name'), 
      (v_item->>'quantity')::INTEGER, 
      (v_item->>'price')::NUMERIC,
      (v_item->>'total')::NUMERIC,
      (v_item->>'originalPrice')::NUMERIC,
      (v_item->>'overrideReason'),
      (v_item->>'authorizedBy')::UUID,
      (v_item->>'batchId')::UUID
    );

    -- Stock Update
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'productId')::UUID AND tenant_id = p_tenant_id;

    -- Batch Update if applicable
    IF (v_item->>'batchId') IS NOT NULL THEN
        UPDATE public.product_batches
        SET quantity_remaining = quantity_remaining - (v_item->>'quantity')::INTEGER,
            status = CASE WHEN quantity_remaining - (v_item->>'quantity')::INTEGER <= 0 THEN 'depleted' ELSE status END
        WHERE id = (v_item->>'batchId')::UUID AND tenant_id = p_tenant_id;
    END IF;
  END LOOP;

  -- 6. Payment Splits Logic
  v_credit_amount := 0;
  
  IF p_payment_splits IS NOT NULL AND jsonb_array_length(p_payment_splits) > 0 THEN
    -- Advanced Split Mode
    FOR v_split IN SELECT * FROM jsonb_array_elements(p_payment_splits)
    LOOP
      INSERT INTO public.payment_splits (
        sale_id, tenant_id, payment_method, amount, 
        transaction_reference, card_last_four, qr_provider
      ) VALUES (
        v_sale_id,
        p_tenant_id,
        v_split->>'method',
        (v_split->>'amount')::NUMERIC,
        v_split->>'reference',
        v_split->>'cardLastFour',
        v_split->>'qrProvider'
      );

      IF (v_split->>'method') = 'credit' THEN
        v_credit_amount := v_credit_amount + (v_split->>'amount')::NUMERIC;
      END IF;
    END LOOP;
  ELSE
    -- Legacy/Simple Mode
    IF p_payment_method = 'credit' THEN
      v_credit_amount := p_total_amount;
    ELSIF p_payment_method = 'mixed' THEN
      v_credit_amount := COALESCE((p_payment_details->>'credit')::NUMERIC, 0);
    END IF;
    
    -- Insert a single split for reporting consistency
    INSERT INTO public.payment_splits (sale_id, tenant_id, payment_method, amount)
    VALUES (v_sale_id, p_tenant_id, p_payment_method, p_total_amount);
  END IF;

  -- 7. Update Customer Credit if applicable
  IF v_credit_amount > 0 AND p_customer_id IS NOT NULL THEN
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

  -- 8. Double-Entry Accounting (Unchanged logic, uses v_credit_amount)
  SELECT id INTO v_acct_cash FROM public.accounts WHERE tenant_id = p_tenant_id AND system_code = 'CASH' LIMIT 1;
  SELECT id INTO v_acct_ar FROM public.accounts WHERE tenant_id = p_tenant_id AND system_code = 'AR' LIMIT 1;
  SELECT id INTO v_acct_sales FROM public.accounts WHERE tenant_id = p_tenant_id AND system_code = 'SALES_REVENUE' LIMIT 1;
  SELECT id INTO v_acct_discount FROM public.accounts WHERE tenant_id = p_tenant_id AND system_code = 'SALES_DISCOUNT' LIMIT 1;
  SELECT id INTO v_acct_vat FROM public.accounts WHERE tenant_id = p_tenant_id AND system_code = 'VAT_PAYABLE' LIMIT 1;

  IF v_acct_cash IS NOT NULL AND v_acct_sales IS NOT NULL THEN
    INSERT INTO public.journal_entries (tenant_id, branch_id, reference_id, reference_type, description, created_by)
    VALUES (p_tenant_id, p_branch_id, v_sale_id, 'SALE', 'Invoice ' || v_invoice_number, p_cashier_id)
    RETURNING id INTO v_je_id;

    -- Debit Cash/Bank (Paid part)
    IF (p_total_amount - v_credit_amount) > 0 THEN
      INSERT INTO public.journal_entry_lines (entry_id, account_id, debit)
      VALUES (v_je_id, v_acct_cash, p_total_amount - v_credit_amount);
    END IF;

    -- Debit AR (Credit part)
    IF v_credit_amount > 0 AND v_acct_ar IS NOT NULL THEN
      INSERT INTO public.journal_entry_lines (entry_id, account_id, debit)
      VALUES (v_je_id, v_acct_ar, v_credit_amount);
    END IF;

    -- Debit Discount
    IF p_discount_amount > 0 AND v_acct_discount IS NOT NULL THEN
      INSERT INTO public.journal_entry_lines (entry_id, account_id, debit)
      VALUES (v_je_id, v_acct_discount, p_discount_amount);
    END IF;

    -- Credit Revenue
    INSERT INTO public.journal_entry_lines (entry_id, account_id, credit)
    VALUES (v_je_id, v_acct_sales, v_sub_total);

    -- Credit VAT
    IF p_vat_amount > 0 AND v_acct_vat IS NOT NULL THEN
      INSERT INTO public.journal_entry_lines (entry_id, account_id, credit)
      VALUES (v_je_id, v_acct_vat, p_vat_amount);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice_number,
    'total_amount', p_total_amount,
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
