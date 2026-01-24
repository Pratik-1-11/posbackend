-- Migration: 027_add_product_returns.sql
-- Description: Add support for product returns and refunds

-- 1. Returns Table
CREATE TABLE IF NOT EXISTS public.returns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    cashier_id UUID REFERENCES public.profiles(id),
    total_refund_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Return Items Table
CREATE TABLE IF NOT EXISTS public.return_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    return_id UUID NOT NULL REFERENCES public.returns(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    refund_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. RLS
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.return_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS returns_isolation ON public.returns;
CREATE POLICY returns_isolation ON public.returns 
    FOR ALL TO authenticated 
    USING (tenant_id = public.get_user_tenant_id()) 
    WITH CHECK (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS return_items_isolation ON public.return_items;
CREATE POLICY return_items_isolation ON public.return_items 
    FOR ALL TO authenticated 
    USING (tenant_id = public.get_user_tenant_id()) 
    WITH CHECK (tenant_id = public.get_user_tenant_id());

-- 4. RPC for Processing Return
CREATE OR REPLACE FUNCTION public.process_pos_return(
    p_sale_id TEXT,
    p_items JSONB,
    p_reason TEXT DEFAULT NULL,
    p_cashier_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_return_id UUID;
    v_real_sale_id UUID;
    v_item JSONB;
    v_total_refund NUMERIC := 0;
    v_tenant_id UUID;
    v_sale_customer_id UUID;
    v_sale_invoice TEXT;
    v_prod_tenant UUID;
    v_is_uuid BOOLEAN;
BEGIN
    -- 1. Security Context
    v_tenant_id := public.get_user_tenant_id();
    IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Tenant not found'; END IF;

    -- 2. Resolve Sale ID (could be UUID or Invoice Number)
    v_is_uuid := p_sale_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
    
    IF v_is_uuid THEN
        SELECT id, customer_id, invoice_number INTO v_real_sale_id, v_sale_customer_id, v_sale_invoice 
        FROM public.sales 
        WHERE id = p_sale_id::UUID AND tenant_id = v_tenant_id;
    ELSE
        SELECT id, customer_id, invoice_number INTO v_real_sale_id, v_sale_customer_id, v_sale_invoice 
        FROM public.sales 
        WHERE invoice_number = p_sale_id AND tenant_id = v_tenant_id;
    END IF;
    
    IF v_real_sale_id IS NULL THEN RAISE EXCEPTION 'Sale not found or unauthorized'; END IF;

    -- 3. Calculate Total Refund from input items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_total_refund := v_total_refund + (v_item->>'refund_amount')::NUMERIC;
    END LOOP;

    -- 4. Insert Return Record
    INSERT INTO public.returns (
        tenant_id, sale_id, cashier_id, total_refund_amount, reason
    ) VALUES (
        v_tenant_id, v_real_sale_id, p_cashier_id, v_total_refund, p_reason
    ) RETURNING id INTO v_return_id;

    -- 5. Process Return Items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- Cross-tenant guard
        SELECT tenant_id INTO v_prod_tenant FROM public.products WHERE id = (v_item->>'product_id')::UUID;
        IF v_prod_tenant != v_tenant_id THEN RAISE EXCEPTION 'Security Error: Cross-tenant product access'; END IF;

        INSERT INTO public.return_items (
            tenant_id, return_id, product_id, quantity, refund_amount
        ) VALUES (
            v_tenant_id, v_return_id, (v_item->>'product_id')::UUID, (v_item->>'quantity')::INTEGER, (v_item->>'refund_amount')::NUMERIC
        );

        -- Restock products
        UPDATE public.products 
        SET stock_quantity = stock_quantity + (v_item->>'quantity')::INTEGER
        WHERE id = (v_item->>'product_id')::UUID;
    END LOOP;

    -- 6. Customer Credit Adjustment (if applicable)
    -- If there's a customer, we should probably record a refund transaction if it was a credit sale.
    -- However, for simplicity, we just record a 'refund' type transaction in the ledger.
    IF v_sale_customer_id IS NOT NULL AND v_total_refund > 0 THEN
        PERFORM add_customer_transaction(
            v_sale_customer_id, 
            'refund', 
            v_total_refund, 
            'Return for INV: ' || v_sale_invoice, 
            v_return_id, 
            p_cashier_id
        );
    END IF;

    RETURN jsonb_build_object(
        'id', v_return_id,
        'status', 'success',
        'refund_amount', v_total_refund
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
