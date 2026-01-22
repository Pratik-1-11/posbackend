-- ==========================================
-- SCHEMA PATCH: SETTINGS TABLE FIX
-- ==========================================

DO $$
BEGIN
    -- 1. Ensure basic settings fields exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'name') THEN
        ALTER TABLE public.settings ADD COLUMN name TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'address') THEN
        ALTER TABLE public.settings ADD COLUMN address TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'phone') THEN
        ALTER TABLE public.settings ADD COLUMN phone TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'email') THEN
        ALTER TABLE public.settings ADD COLUMN email TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'pan') THEN
        ALTER TABLE public.settings ADD COLUMN pan TEXT;
    END IF;
    
    -- 2. Add Json/Jsonb fields for grouped settings
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'receipt_settings') THEN
        ALTER TABLE public.settings ADD COLUMN receipt_settings JSONB DEFAULT '{}'::jsonb;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'notification_settings') THEN
        ALTER TABLE public.settings ADD COLUMN notification_settings JSONB DEFAULT '{}'::jsonb;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'security_settings') THEN
        ALTER TABLE public.settings ADD COLUMN security_settings JSONB DEFAULT '{}'::jsonb;
    END IF;

    -- 3. Renaming / mapping logic (in case old columns exist)
    -- Map old 'footer_message' etc. if they existed standalone, otherwise key fields are handled above.
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'footer_message') THEN
        ALTER TABLE public.settings ADD COLUMN footer_message TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'tax_rate') THEN
        ALTER TABLE public.settings ADD COLUMN tax_rate NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'currency') THEN
        ALTER TABLE public.settings ADD COLUMN currency TEXT DEFAULT 'NPR';
    END IF;

     -- 4. Ensure RLS Policy
    ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "Users view tenant settings" ON public.settings;
    CREATE POLICY "Users view tenant settings"
    ON public.settings FOR SELECT
    USING (tenant_id = public.get_user_tenant_id());

    DROP POLICY IF EXISTS "Admins manage tenant settings" ON public.settings;
    CREATE POLICY "Admins manage tenant settings"
    ON public.settings FOR ALL
    USING (
        public.is_vendor_admin() AND
        (tenant_id = public.get_user_tenant_id())
    )
    WITH CHECK (
        public.is_vendor_admin() AND
        (tenant_id = public.get_user_tenant_id())
    );

END $$;
