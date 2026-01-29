-- ==========================================
-- PHASE 5: INTEGRATIONS & DATA SOVEREIGNTY
-- ==========================================

-- 1. API Keys System
CREATE TABLE IF NOT EXISTS public.tenant_api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL, -- e.g., "Zapier Integration"
    key_prefix TEXT NOT NULL,
    key_hash TEXT NOT NULL, -- Store hashed key (argon2 or similar, but for simplicity here we might use sha256)
    scopes TEXT[] DEFAULT ARRAY['read_only'], -- 'read_only', 'read_write'
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for API Keys
ALTER TABLE public.tenant_api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "api_keys_tenant_isolation" ON public.tenant_api_keys 
FOR ALL TO authenticated 
USING (tenant_id = public.get_user_tenant_id())
WITH CHECK (tenant_id = public.get_user_tenant_id());

-- 2. Data Export RPC
-- Aggregates core tenant data into a single JSONB blob
CREATE OR REPLACE FUNCTION public.export_tenant_data(p_tenant_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_data JSONB;
BEGIN
    -- Security Check (Caller must be Super Admin or the Tenant Owner)
    IF NOT (
        public.is_super_admin() OR 
        (auth.uid() IN (SELECT id FROM public.profiles WHERE tenant_id = p_tenant_id AND role IN ('VENDOR_ADMIN')))
    ) THEN
        RAISE EXCEPTION 'Unauthorized data export request';
    END IF;

    SELECT jsonb_build_object(
        'metadata', (SELECT to_jsonb(t) FROM public.tenants t WHERE id = p_tenant_id),
        'products', (SELECT jsonb_agg(p) FROM public.products p WHERE tenant_id = p_tenant_id),
        'customers', (SELECT jsonb_agg(c) FROM public.customers c WHERE tenant_id = p_tenant_id),
        'sales', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'sale', s,
                    'items', (SELECT jsonb_agg(si) FROM public.sale_items si WHERE sale_id = s.id)
                )
            ) 
            FROM public.sales s WHERE tenant_id = p_tenant_id
        ),
        'generated_at', NOW()
    ) INTO v_data;

    RETURN v_data;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
