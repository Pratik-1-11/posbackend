-- Migration: 037_batch_tracking_and_profit_analysis.sql
-- Purpose: Implement Product Batch Tracking and Advanced Profit Analysis

-- 1. Create Product Batches Table
CREATE TABLE IF NOT EXISTS public.product_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
    branch_id UUID REFERENCES public.branches(id),
    product_id UUID REFERENCES public.products(id) NOT NULL,
    batch_number TEXT NOT NULL,
    
    -- Batch-specific pricing (overrides product-level price if set)
    cost_price NUMERIC(15, 2) NOT NULL,
    selling_price NUMERIC(15, 2),
    
    quantity_received INTEGER NOT NULL DEFAULT 0,
    quantity_remaining INTEGER NOT NULL DEFAULT 0,
    
    manufacture_date DATE,
    expiry_date DATE,
    
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'expired', 'recalled', 'depleted')),
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Add batch_id to sale_items
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS batch_id UUID REFERENCES public.product_batches(id);

-- 3. Enable RLS on Product Batches
ALTER TABLE public.product_batches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View batches in own tenant" ON public.product_batches;
CREATE POLICY "View batches in own tenant" ON public.product_batches
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- 4. Profit Analysis View
CREATE OR REPLACE VIEW public.vw_profit_analysis AS
SELECT 
    si.id as item_id,
    s.id as sale_id,
    s.tenant_id,
    s.branch_id,
    s.created_at as sale_date,
    p.id as product_id,
    p.name as product_name,
    si.quantity,
    si.unit_price as selling_price,
    -- Use cost price from batch if available, else from product record
    COALESCE(pb.cost_price, p.cost_price, 0) as cost_price,
    (si.unit_price - COALESCE(pb.cost_price, p.cost_price, 0)) * si.quantity as line_profit,
    ((si.unit_price - COALESCE(pb.cost_price, p.cost_price, 0)) / NULLIF(si.unit_price, 0)) * 100 as profit_margin_percent
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
JOIN public.products p ON si.product_id = p.id
LEFT JOIN public.product_batches pb ON si.batch_id = pb.id
WHERE s.status = 'completed';

-- 5. Expiring Products Function
CREATE OR REPLACE FUNCTION public.get_expiring_products(p_tenant_id UUID, p_days_threshold INTEGER DEFAULT 30)
RETURNS TABLE (
    batch_id UUID,
    product_id UUID,
    product_name TEXT,
    batch_number TEXT,
    expiry_date DATE,
    days_left INTEGER,
    quantity INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pb.id,
        p.id,
        p.name,
        pb.batch_number,
        pb.expiry_date,
        (pb.expiry_date - CURRENT_DATE)::INTEGER,
        pb.quantity_remaining
    FROM public.product_batches pb
    JOIN public.products p ON pb.product_id = p.id
    WHERE pb.tenant_id = p_tenant_id
      AND pb.status = 'active'
      AND pb.expiry_date IS NOT NULL
      AND pb.expiry_date <= (CURRENT_DATE + p_days_threshold)
    ORDER BY pb.expiry_date ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Updated process_pos_sale RPC to handle batch_id and update batch stock
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
      (v_item->>'batchId')::UUID -- New Batch Field
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

    -- Update Global Product Stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'productId')::UUID AND tenant_id = p_tenant_id;

    -- Update Batch Stock (if applicable)
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
