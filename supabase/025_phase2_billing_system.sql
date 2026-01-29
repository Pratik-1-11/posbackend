-- ==========================================
-- PHASE 2: BILLING, INVOICING & AUTO-SUSPENSION
-- ==========================================

-- 1. Create Tenant Invoices Table
CREATE TABLE IF NOT EXISTS public.tenant_invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES public.plans(id),
    invoice_number TEXT UNIQUE NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    currency TEXT DEFAULT 'NPR',
    status TEXT DEFAULT 'unpaid' CHECK (status IN ('paid', 'unpaid', 'overdue', 'void')),
    billing_reason TEXT, -- e.g., 'subscription_renewal', 'tier_upgrade'
    billing_period_start TIMESTAMPTZ,
    billing_period_end TIMESTAMPTZ,
    due_date TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Create Tenant Payments Table
CREATE TABLE IF NOT EXISTS public.tenant_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    invoice_id UUID REFERENCES public.tenant_invoices(id),
    amount NUMERIC(10, 2) NOT NULL,
    payment_method TEXT, -- e.g., 'stripe', 'esewa', 'bank_transfer', 'cash'
    transaction_id TEXT, -- External gateway reference
    status TEXT CHECK (status IN ('success', 'pending', 'failed', 'refunded')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Configuration Table (Super Admin Settings)
CREATE TABLE IF NOT EXISTS public.platform_billing_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.platform_billing_config (key, value)
VALUES 
('suspension_policy', '{
    "grace_period_days": 3,
    "auto_suspend": true,
    "notify_before_days": [7, 3, 1]
}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 4. RPC: Auto-Suspend Expired Tenants
-- This function should be run by a cron job (e.g. Supabase Edge Function or pg_cron)
CREATE OR REPLACE FUNCTION public.check_and_suspend_expired_tenants()
RETURNS TABLE (suspended_count INTEGER) AS $$
DECLARE
    v_grace_days INTEGER;
BEGIN
    SELECT (value->>'grace_period_days')::INTEGER INTO v_grace_days 
    FROM public.platform_billing_config WHERE key = 'suspension_policy';
    
    -- Use a CTE to perform the update and count affected rows
    RETURN QUERY
    WITH affected AS (
        UPDATE public.tenants
        SET 
            subscription_status = 'suspended',
            is_active = FALSE,
            updated_at = NOW()
        WHERE 
            subscription_status = 'active'
            AND subscription_end_date < (NOW() - (v_grace_days || ' days')::INTERVAL)
            AND deleted_at IS NULL
        RETURNING id
    )
    SELECT COUNT(*)::INTEGER FROM affected;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Generate Renewal Invoice
CREATE OR REPLACE FUNCTION public.generate_tenant_renewal_invoice(p_tenant_id UUID)
RETURNS UUID AS $$
DECLARE
    v_plan_id UUID;
    v_amount NUMERIC;
    v_currency TEXT;
    v_invoice_id UUID;
    v_inv_number TEXT;
    v_interval TEXT;
BEGIN
    SELECT plan_id, plan_interval INTO v_plan_id, v_interval 
    FROM public.tenants WHERE id = p_tenant_id;
    
    SELECT 
        CASE WHEN v_interval = 'yearly' THEN price_yearly ELSE price_monthly END,
        currency 
    INTO v_amount, v_currency
    FROM public.plans WHERE id = v_plan_id;
    
    v_inv_number := 'SUB-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 1000)::text, 4, '0');
    
    INSERT INTO public.tenant_invoices (
        tenant_id, plan_id, invoice_number, amount, currency, status, 
        billing_reason, due_date, billing_period_start, billing_period_end
    ) VALUES (
        p_tenant_id, v_plan_id, v_inv_number, v_amount, v_currency, 'unpaid',
        'subscription_renewal', NOW() + INTERVAL '7 days', NOW(), 
        CASE WHEN v_interval = 'yearly' THEN NOW() + INTERVAL '1 year' ELSE NOW() + INTERVAL '1 month' END
    ) RETURNING id INTO v_invoice_id;
    
    RETURN v_invoice_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
