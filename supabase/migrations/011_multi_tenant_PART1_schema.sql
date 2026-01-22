-- ==========================================
-- SAFE MULTI-TENANT MIGRATION (Checks table existence)
-- For existing POS database
-- Version: 1.1 - Safe Edition
-- ==========================================

-- PHASE 1: CREATE TENANT INFRASTRUCTURE
-- ==========================================

-- 1.1 Create Tenants Table
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Tenant Identity
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  type TEXT NOT NULL DEFAULT 'vendor' CHECK (type IN ('super', 'vendor')),
  
  -- Business Information
  business_name TEXT,
  business_registration_number TEXT,
  contact_email TEXT NOT NULL,
  contact_phone TEXT,
  address TEXT,
  
  -- Subscription & Status
  subscription_tier TEXT DEFAULT 'basic' CHECK (subscription_tier IN ('basic', 'pro', 'enterprise')),
  subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'trial', 'suspended', 'cancelled')),
  subscription_started_at TIMESTAMPTZ,
  subscription_expires_at TIMESTAMPTZ,
  
  -- Settings & Configuration
  settings JSONB DEFAULT '{}'::jsonb,
  
  -- Status & Metadata
  is_active BOOLEAN DEFAULT TRUE,
  onboarded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id)
);

-- 1.2 Create Indexes for Tenants
CREATE INDEX IF NOT EXISTS idx_tenants_slug ON public.tenants(slug);
CREATE INDEX IF NOT EXISTS idx_tenants_type ON public.tenants(type);
CREATE INDEX IF NOT EXISTS idx_tenants_status ON public.tenants(subscription_status);
CREATE INDEX IF NOT EXISTS idx_tenants_active ON public.tenants(is_active) WHERE is_active = TRUE;

-- 1.3 Create Audit Logs Table
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Who & Where
  actor_id UUID REFERENCES auth.users(id),
  actor_role TEXT,
  tenant_id UUID REFERENCES public.tenants(id),
  
  -- What & When
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  changes JSONB,
  
  -- Context
  ip_address INET,
  user_agent TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant ON public.audit_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);

-- PHASE 2: ADD TENANT_ID TO EXISTING TABLES (with existence checks)
-- ==========================================

-- Helper function to safely add column
DO $$
BEGIN
  -- Add to profiles
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
    ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to branches (if exists)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'branches') THEN
    ALTER TABLE public.branches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to products
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
    ALTER TABLE public.products ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to categories
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'categories') THEN
    ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to suppliers
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'suppliers') THEN
    ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to customers
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'customers') THEN
    ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to sales
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to expenses
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expenses') THEN
    ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to purchases
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'purchases') THEN
    ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;

  -- Add to settings
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'settings') THEN
    ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
  END IF;
END $$;

-- PHASE 3: CREATE DEFAULT TENANTS & BACKFILL DATA
-- ==========================================

-- 3.1 Insert default "super" tenant for platform admin
INSERT INTO public.tenants (id, name, slug, type, contact_email, subscription_status, is_active)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'Platform Admin',
  'platform-admin',
  'super',
  'admin@platform.com',
  'active',
  TRUE
)
ON CONFLICT (id) DO NOTHING;

-- 3.2 Insert default vendor tenant for existing data
INSERT INTO public.tenants (id, name, slug, type, contact_email, subscription_status, is_active)
VALUES (
  '00000000-0000-0000-0000-000000000002',
  'Default Store',
  'default-store',
  'vendor',
  'store@example.com',
  'active',
  TRUE
)
ON CONFLICT (id) DO NOTHING;

-- 3.3 Backfill tenant_id for existing data
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
    UPDATE public.profiles SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'branches') THEN
    UPDATE public.branches SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
    UPDATE public.products SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'categories') THEN
    UPDATE public.categories SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'suppliers') THEN
    UPDATE public.suppliers SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'customers') THEN
    UPDATE public.customers SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    UPDATE public.sales SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expenses') THEN
    UPDATE public.expenses SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'purchases') THEN
    UPDATE public.purchases SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'settings') THEN
    UPDATE public.settings SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;
END $$;

-- PHASE 4: MAKE TENANT_ID NOT NULL (with checks)
-- ==========================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
    ALTER TABLE public.profiles ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
    ALTER TABLE public.products ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'customers') THEN
    ALTER TABLE public.customers ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    ALTER TABLE public.sales ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'categories') THEN
    ALTER TABLE public.categories ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'suppliers') THEN
    ALTER TABLE public.suppliers ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'expenses') THEN
    ALTER TABLE public.expenses ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'purchases') THEN
    ALTER TABLE public.purchases ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'settings') THEN
    ALTER TABLE public.settings ALTER COLUMN tenant_id SET NOT NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'branches') THEN
    ALTER TABLE public.branches ALTER COLUMN tenant_id SET NOT NULL;
  END IF;
END $$;

--PHASE 5: CREATE TENANT-AWARE INDEXES
-- ==========================================

DO $$
BEGIN
  -- Profiles indexes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
    CREATE INDEX IF NOT EXISTS idx_profiles_tenant ON public.profiles(tenant_id);
    CREATE INDEX IF NOT EXISTS idx_profiles_tenant_role ON public.profiles(tenant_id, role);
    CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
  END IF;

  -- Products indexes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
    CREATE INDEX IF NOT EXISTS idx_products_tenant ON public.products(tenant_id);
    CREATE INDEX IF NOT EXISTS idx_products_tenant_active ON public.products(tenant_id, is_active);
  END IF;

  -- Customers indexes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'customers') THEN
    CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers(tenant_id);
  END IF;

  -- Sales indexes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sales') THEN
    CREATE INDEX IF NOT EXISTS idx_sales_tenant ON public.sales(tenant_id);
    CREATE INDEX IF NOT EXISTS idx_sales_tenant_date ON public.sales(tenant_id, created_at DESC);
  END IF;
END $$;

-- PHASE 6: UPDATE ROLE CONSTRAINTS
-- ==========================================

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
  CHECK (role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER',  'super_admin', 'branch_admin', 'cashier', 'inventory_manager', 'waiter', 'manager', 'admin'));

-- Add unique constraint for email per tenant
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_tenant_email_key;
-- Note: Not adding this yet as it might conflict with existing data

-- SUCCESS MESSAGE
DO $$
DECLARE
  v_tenant_count INT;
  v_profile_count INT;
  v_product_count INT;
BEGIN
  SELECT COUNT(*) INTO v_tenant_count FROM public.tenants;
  SELECT COUNT(*) INTO v_profile_count FROM public.profiles WHERE tenant_id IS NOT NULL;
  SELECT COUNT(*) INTO v_product_count FROM public.products WHERE tenant_id IS NOT NULL;
  
  RAISE NOTICE '';
  RAISE NOTICE '==========================================';
  RAISE NOTICE '✅ PHASE 1-6 COMPLETED SUCCESSFULLY!';
  RAISE NOTICE '==========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Migration Status:';
  RAISE NOTICE '- Total tenants: %', v_tenant_count;
  RAISE NOTICE '- Profiles with tenant: %', v_profile_count;
  RAISE NOTICE '- Products with tenant: %', v_product_count;
  RAISE NOTICE '';
  RAISE NOTICE 'Next: Run PART 2 migration for RLS policies and functions';
  RAISE NOTICE '';
END $$;
