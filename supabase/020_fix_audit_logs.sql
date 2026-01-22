-- Fix Audit Logs Table
-- Run this in Supabase SQL Editor

-- 1. Check/Add tenant_id
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.audit_logs ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
    END IF;
END $$;

-- 2. Check/Add entity_type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'entity_type') THEN
        ALTER TABLE public.audit_logs ADD COLUMN entity_type TEXT DEFAULT 'system';
    END IF;
END $$;

-- 3. Check/Add entity_id
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'entity_id') THEN
        ALTER TABLE public.audit_logs ADD COLUMN entity_id UUID;
    END IF;
END $$;

-- 4. Check/Add actor_id
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'actor_id') THEN
        ALTER TABLE public.audit_logs ADD COLUMN actor_id UUID REFERENCES auth.users(id);
    END IF;
END $$;

-- 5. Now create indexes (Non-Concurrent)
CREATE INDEX IF NOT EXISTS idx_audit_tenant_date ON public.audit_logs(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON public.audit_logs(entity_type, entity_id);
