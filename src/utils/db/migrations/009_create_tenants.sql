-- ==========================================
-- ULTRA-SIMPLE MULTI-TENANT MIGRATION
-- Absolute minimum - just add tenant support
-- Run this first, then we'll do the rest
-- ==========================================

-- Step 1: Create tenants table
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  type TEXT NOT NULL DEFAULT 'vendor',
  contact_email TEXT NOT NULL,
  subscription_status TEXT DEFAULT 'active',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Step 2: Insert default tenants
INSERT INTO public.tenants (id, name, slug, type, contact_email, is_active)
VALUES 
  ('00000000-0000-0000-0000-000000000001', 'Platform Admin', 'platform-admin', 'super', 'admin@platform.com', TRUE),
  ('00000000-0000-0000-0000-000000000002', 'Default Store', 'default-store', 'vendor', 'store@example.com', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Step 3: Add tenant_id to profiles
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS tenant_id UUID;

-- Step 4: Add tenant_id to products
ALTER TABLE public.products 
ADD COLUMN IF NOT EXISTS tenant_id UUID;

-- Step 5: Add tenant_id to customers
ALTER TABLE public.customers 
ADD COLUMN IF NOT EXISTS tenant_id UUID;

-- Step 6: Add tenant_id to sales
ALTER TABLE public.sales 
ADD COLUMN IF NOT EXISTS tenant_id UUID;

-- Step 7: Add tenant_id to categories (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'categories') THEN
    ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS tenant_id UUID;
  END IF;
END $$;

-- Step 8: Add tenant_id to suppliers (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'suppliers') THEN
    ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS tenant_id UUID;
  END IF;
END $$;

-- Step 9: Add tenant_id to expenses (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'expenses') THEN
    ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS tenant_id UUID;
  END IF;
END $$;

-- Step 10: Add tenant_id to purchases (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'purchases') THEN
    ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS tenant_id UUID;
  END IF;
END $$;

-- Step 11: Backfill existing data with default tenant
UPDATE public.profiles SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.products SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.customers SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.sales SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;

-- Step 12: Backfill optional tables (if they exist)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'categories') THEN
    UPDATE public.categories SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'suppliers') THEN
    UPDATE public.suppliers SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'expenses') THEN
    UPDATE public.expenses SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'purchases') THEN
    UPDATE public.purchases SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
  END IF;
END $$;
