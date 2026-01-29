-- ==========================================
-- PHASE 4: SUPPORT & BROADCAST SYSTEM
-- ==========================================

-- 1. Platform Announcements (Global Notifications)
CREATE TABLE IF NOT EXISTS public.platform_announcements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT DEFAULT 'info' CHECK (type IN ('info', 'warning', 'critical', 'success')),
    target_plan_id UUID REFERENCES public.plans(id), -- NULL means everyone
    starts_at TIMESTAMPTZ DEFAULT NOW(),
    ends_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for Announcements (Visible to everyone authenticated)
ALTER TABLE public.platform_announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "announcements_read_all" ON public.platform_announcements 
FOR SELECT TO authenticated USING (is_active = TRUE AND (ends_at IS NULL OR ends_at > NOW()));

-- 2. Support Access Logs (For Impersonation Auditee)
CREATE TABLE IF NOT EXISTS public.support_access_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_id UUID NOT NULL REFERENCES auth.users(id),
    target_user_id UUID NOT NULL REFERENCES auth.users(id),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id),
    reason TEXT,
    accessed_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- 3. RPC: Get Tenant Health Score
CREATE OR REPLACE FUNCTION public.calculate_tenant_health(p_tenant_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_last_sale TIMESTAMPTZ;
    v_score INTEGER := 100;
    v_days_since_active INTEGER;
BEGIN
    -- 1. Check last sale activity
    SELECT MAX(created_at) INTO v_last_sale FROM public.sales WHERE tenant_id = p_tenant_id;
    
    IF v_last_sale IS NULL THEN
        v_score := v_score - 40; -- Low health for new/inactive nodes
    ELSE
        v_days_since_active := EXTRACT(DAY FROM (NOW() - v_last_sale));
        IF v_days_since_active > 7 THEN v_score := v_score - 20; END IF;
        IF v_days_since_active > 30 THEN v_score := v_score - 30; END IF;
    END IF;

    -- 2. Check billing status
    IF EXISTS (SELECT 1 FROM public.tenant_invoices WHERE tenant_id = p_tenant_id AND status = 'overdue') THEN
        v_score := v_score - 30;
    END IF;

    -- 3. Check profiles count vs plan limit (Utilization)
    -- (Simplified for now)
    
    RETURN GREATEST(v_score, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
