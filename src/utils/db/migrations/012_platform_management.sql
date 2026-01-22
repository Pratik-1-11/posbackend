-- Migration: Add Platform Settings & Resource Quotas
-- Author: Antigravity

-- 1. Create Platform Settings Table
CREATE TABLE IF NOT EXISTS public.platform_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by UUID REFERENCES auth.users(id)
);

-- 2. Seed default settings
INSERT INTO public.platform_settings (key, value, description)
VALUES 
  ('maintenance_mode', '{"enabled": false, "message": "System is undergoing scheduled maintenance."}', 'Global maintenance mode toggle'),
  ('registration_open', '{"enabled": true}', 'Toggle for new tenant registration'),
  ('global_feature_flags', '{"accounting_v2": false, "new_pos_ui": true, "ai_insights": false}', 'Platform-wide feature gate'),
  ('system_notifications', '[]', 'Global banners for all tenants')
ON CONFLICT (key) DO NOTHING;

-- 3. Add Resource Quotas to Tenants
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS resource_limits JSONB DEFAULT '{
  "max_users": 5,
  "max_products": 100,
  "max_branches": 1,
  "storage_gb": 1,
  "features": ["inventory", "pos", "reports"]
}'::jsonb;

-- 4. Create System Audit Logs for Platform changes
-- (Already handled by audit_logs, but we'll ensure index)
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);

-- Success message
DO $$
BEGIN
  RAISE NOTICE '✅ Platform Management Infrastructure Ready';
END $$;
