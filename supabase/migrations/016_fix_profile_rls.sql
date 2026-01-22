-- FINAL SECURITY & RLS CONFIGURATION
-- This script replaces all previous RLS attempts with a clean, performant set of rules.

-- 1. CLEANUP ALL EXISTING POLICIES (Sales & Profiles)
DO $$
DECLARE
    pol record;
BEGIN
    FOR pol IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('sales', 'sale_items', 'products', 'profiles', 'customers'))
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
    END LOOP;
END $$;

-- 2. ENABLE RLS
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- 3. PROFILE ACCESS (Crucial for token resolution)
-- Everyone can read their own profile. Super Admins can read all.
CREATE POLICY "profiles_read_own" ON public.profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "profiles_read_super" ON public.profiles FOR SELECT USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN');
CREATE POLICY "profiles_read_tenant" ON public.profiles FOR SELECT USING (tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID);

-- 4. SALES ISOLATION
-- Allow Service Role to do everything (for audit/backend)
CREATE POLICY "sales_service_role" ON public.sales FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Allow authenticated users to see their tenant's sales
CREATE POLICY "sales_tenant_isolation" ON public.sales FOR ALL TO authenticated 
USING (
  tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID
  OR 
  (auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN'
)
WITH CHECK (
  tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID
  OR 
  (auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN'
);

-- 5. SALE ITEMS ISOLATION
CREATE POLICY "sale_items_service_role" ON public.sale_items FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "sale_items_tenant_isolation" ON public.sale_items FOR ALL TO authenticated 
USING (
  tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID
  OR 
  (auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN'
);

-- 6. PRODUCTS ISOLATION
CREATE POLICY "products_service_role" ON public.products FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "products_tenant_select" ON public.products FOR SELECT TO authenticated 
USING (
  tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID
  OR 
  (auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN'
);

-- 7. RE-GRANTS
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
