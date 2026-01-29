-- Migration: 036_price_override_system.sql
-- Purpose: Implement secure price overrides with manager authorization and audit trail

-- 1. Add manager_pin to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS manager_pin_hash TEXT;

-- 2. Update sale_items to track overrides
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS original_unit_price NUMERIC(15, 2);
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS override_reason TEXT;
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS authorized_by UUID REFERENCES public.profiles(id);

-- 3. Create Price Overrides Log for detailed auditing
CREATE TABLE IF NOT EXISTS public.price_overrides_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
    sale_id UUID REFERENCES public.sales(id), -- Nullable if logged before sale is completed
    product_id UUID REFERENCES public.products(id) NOT NULL,
    cashier_id UUID REFERENCES public.profiles(id) NOT NULL,
    manager_id UUID REFERENCES public.profiles(id) NOT NULL,
    original_price NUMERIC(15, 2) NOT NULL,
    new_price NUMERIC(15, 2) NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Enable RLS on overrides log
ALTER TABLE public.price_overrides_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View overrides in own tenant" ON public.price_overrides_log;
CREATE POLICY "View overrides in own tenant" ON public.price_overrides_log
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- 5. Updated process_pos_sale RPC to handle override data
-- We will replace the previous one with an updated version that maps override fields
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

  -- 2. Generate Invoice Number
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 100000)::text, 5, '0');

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

  -- 5. Insert Sale Items (including override fields)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.sale_items (
        sale_id, product_id, product_name, quantity, unit_price, total_price,
        original_unit_price, override_reason, authorized_by
    )
    VALUES (
      v_sale_id, 
      (v_item->>'productId')::UUID, 
      (v_item->>'name'), 
      (v_item->>'quantity')::INTEGER, 
      (v_item->>'price')::NUMERIC,
      (v_item->>'total')::NUMERIC,
      (v_item->>'originalPrice')::NUMERIC, -- New Field
      (v_item->>'overrideReason'),          -- New Field
      (v_item->>'authorizedBy')::UUID       -- New Field
    );

    -- Log override if it occurred
    IF (v_item->>'authorizedBy') IS NOT NULL THEN
        INSERT INTO public.price_overrides_log (
            tenant_id, sale_id, product_id, cashier_id, manager_id, 
            original_price, new_price, reason
        ) VALUES (
            p_tenant_id, v_sale_id, (v_item->>'productId')::UUID, p_cashier_id, (v_item->>'authorizedBy')::UUID,
            (v_item->>'originalPrice')::NUMERIC, (v_item->>'price')::NUMERIC, (v_item->>'overrideReason')
        );
    END IF;

    -- Update Stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'productId')::UUID AND tenant_id = p_tenant_id;
  END LOOP;

  -- 6. Credit Logic (Same as before)
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
