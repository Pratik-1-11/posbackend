-- ==========================================
-- PHASE 1: ROBUST PLAN SYSTEM & SOFT DELETE
-- ==========================================

-- 1. Create Plans Table
CREATE TABLE IF NOT EXISTS public.plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    description TEXT,
    price_monthly NUMERIC(10, 2) NOT NULL DEFAULT 0,
    price_yearly NUMERIC(10, 2) NOT NULL DEFAULT 0,
    currency TEXT DEFAULT 'NPR',
    
    -- Resource Limits
    max_users INTEGER DEFAULT 5,
    max_stores INTEGER DEFAULT 1,
    max_products INTEGER DEFAULT 500,
    max_customers INTEGER DEFAULT 1000,
    
    -- Feature Flags
    features JSONB DEFAULT '{
        "api_access": false,
        "custom_reports": false,
        "inventory_v2": false,
        "loyalty_program": false,
        "multi_branch_sync": false
    }'::jsonb,
    
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Seed Initial Plans
INSERT INTO public.plans (name, slug, description, price_monthly, price_yearly, max_users, max_stores, max_products, features)
VALUES 
('Starter Cluster', 'basic', 'Perfect for local single-unit retail businesses.', 999, 9990, 5, 1, 500, '{
    "api_access": false,
    "custom_reports": false,
    "inventory_v2": true,
    "loyalty_program": false,
    "multi_branch_sync": false
}'),
('Business Pro', 'pro', 'Advanced features for growing multi-store networks.', 2999, 29990, 25, 5, 5000, '{
    "api_access": true,
    "custom_reports": true,
    "inventory_v2": true,
    "loyalty_program": true,
    "multi_branch_sync": true
}'),
('Enterprise Hub', 'enterprise', 'Unlimited scale for high-volume retail enterprises.', 9999, 99990, 99999, 99999, 99999, '{
    "api_access": true,
    "custom_reports": true,
    "inventory_v2": true,
    "loyalty_program": true,
    "multi_branch_sync": true
}')
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    price_monthly = EXCLUDED.price_monthly,
    price_yearly = EXCLUDED.price_yearly,
    max_users = EXCLUDED.max_users,
    max_stores = EXCLUDED.max_stores,
    max_products = EXCLUDED.max_products,
    features = EXCLUDED.features;

-- 3. Update Tenants Table
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES public.plans(id);
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS subscription_end_date TIMESTAMPTZ;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS plan_interval TEXT DEFAULT 'monthly' CHECK (plan_interval IN ('monthly', 'yearly'));

-- 4. Data Migration: Link existing tenants to plans
UPDATE public.tenants t
SET plan_id = p.id
FROM public.plans p
WHERE t.subscription_tier = p.slug;

-- 5. Update RLS for Soft Delete
-- We need to update existing policies to check for deleted_at IS NULL
DO $$
DECLARE 
    pol record;
BEGIN
    -- This is a bit complex to automate for all tables, but critical for tenants
    DROP POLICY IF EXISTS tenants_own_read ON public.tenants;
    CREATE POLICY tenants_own_read ON public.tenants 
    FOR SELECT USING (id = public.get_user_tenant_id() AND deleted_at IS NULL);
END $$;

-- 6. Helper Function Check Plan Limits
CREATE OR REPLACE FUNCTION public.check_tenant_limit(p_tenant_id UUID, p_limit_key TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_limit INTEGER;
    v_current INTEGER;
    v_plan_id UUID;
BEGIN
    SELECT plan_id INTO v_plan_id FROM public.tenants WHERE id = p_tenant_id;
    
    EXECUTE format('SELECT %I FROM public.plans WHERE id = $1', p_limit_key)
    USING v_plan_id
    INTO v_limit;
    
    -- Dynamic count based on key
    IF p_limit_key = 'max_users' THEN
        SELECT COUNT(*) INTO v_current FROM public.profiles WHERE tenant_id = p_tenant_id AND status != 'inactive';
    ELSIF p_limit_key = 'max_stores' THEN
        SELECT COUNT(*) INTO v_current FROM public.branches WHERE tenant_id = p_tenant_id AND is_active = TRUE;
    ELSIF p_limit_key = 'max_products' THEN
        SELECT COUNT(*) INTO v_current FROM public.products WHERE tenant_id = p_tenant_id AND is_active = TRUE;
    END IF;
    
    RETURN v_current < v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
