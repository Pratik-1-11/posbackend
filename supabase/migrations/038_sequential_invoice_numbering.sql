-- Migration: 038_sequential_invoice_numbering.sql
-- Purpose: Implement branch-aware sequential gap-free invoice numbering for IRD compliance

-- 1. Create Invoice Counters Table
CREATE TABLE IF NOT EXISTS public.invoice_counters (
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
    fiscal_year TEXT NOT NULL,
    current_number INT NOT NULL DEFAULT 0,
    PRIMARY KEY (tenant_id, branch_id, fiscal_year)
);

-- Enable RLS
ALTER TABLE public.invoice_counters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View counters in own tenant" ON public.invoice_counters;
CREATE POLICY "View counters in own tenant" ON public.invoice_counters
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- 2. Function to Get Next Invoice Number
CREATE OR REPLACE FUNCTION public.get_next_invoice_number(p_tenant_id UUID, p_branch_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_fiscal_year TEXT;
    v_next_number INT;
    v_branch_code TEXT;
BEGIN
    v_fiscal_year := to_char(NOW(), 'YYYY');

    -- get branch code
    IF p_branch_id IS NOT NULL THEN
        SELECT SUBSTRING(name, 1, 3) INTO v_branch_code FROM public.branches WHERE id = p_branch_id AND tenant_id = p_tenant_id;
    END IF;

    IF v_branch_code IS NULL THEN
        v_branch_code := 'M';
    END IF;

    v_branch_code := UPPER(v_branch_code);

    -- atomic increment with gap-free guarantee under row lock
    INSERT INTO public.invoice_counters (tenant_id, branch_id, fiscal_year, current_number)
    VALUES (p_tenant_id, p_branch_id, v_fiscal_year, 1)
    ON CONFLICT (tenant_id, branch_id, fiscal_year)
    DO UPDATE SET current_number = public.invoice_counters.current_number + 1
    RETURNING current_number INTO v_next_number;

    RETURN 'INV-' || v_branch_code || '-' || v_fiscal_year || '-' || LPAD(v_next_number::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Update process_pos_sale to use the sequential numbering
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

  -- 2. Generate Invoice Number SEQUENTIALLY
  v_invoice_number := public.get_next_invoice_number(p_tenant_id, p_branch_id);

  -- 3. Calculate Sub-total
  v_sub_total := p_total_amount + p_discount_amount;

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

  -- 5. Insert Sale Items (including override fields and batch_id)
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

    IF (v_item->>'authorizedBy') IS NOT NULL THEN
        INSERT INTO public.price_overrides_log (
            tenant_id, sale_id, product_id, cashier_id, manager_id, 
            original_price, new_price, reason
        ) VALUES (
            p_tenant_id, v_sale_id, (v_item->>'productId')::UUID, p_cashier_id, (v_item->>'authorizedBy')::UUID,
            (v_item->>'originalPrice')::NUMERIC, (v_item->>'price')::NUMERIC, (v_item->>'overrideReason')
        );
    END IF;

    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'productId')::UUID AND tenant_id = p_tenant_id;

    IF (v_item->>'batchId') IS NOT NULL THEN
        UPDATE public.product_batches
        SET quantity_remaining = quantity_remaining - (v_item->>'quantity')::INTEGER,
            status = CASE WHEN quantity_remaining - (v_item->>'quantity')::INTEGER <= 0 THEN 'depleted' ELSE status END
        WHERE id = (v_item->>'batchId')::UUID AND tenant_id = p_tenant_id;
    END IF;
  END LOOP;

  -- 6. Credit Logic
  IF (p_payment_method = 'credit' OR (p_payment_method = 'mixed' AND (p_payment_details->>'credit')::NUMERIC > 0)) AND p_customer_id IS NOT NULL THEN
    INSERT INTO public.customer_transactions (
      tenant_id, customer_id, transaction_type, amount, description, reference_id, cashier_id
    ) VALUES (
      p_tenant_id, p_customer_id, 'sale', COALESCE((p_payment_details->>'credit')::NUMERIC, p_total_amount), 
      'POS Sale: ' || v_invoice_number, v_sale_id, p_cashier_id
    );

    UPDATE public.customers
    SET total_credit = total_credit + COALESCE((p_payment_details->>'credit')::NUMERIC, p_total_amount),
        updated_at = NOW()
    WHERE id = p_customer_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_sale_id,
    'invoice_number', v_invoice_number,
    'total_amount', p_total_amount,
    'status', 'success'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
