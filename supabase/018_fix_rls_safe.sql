-- ============================================================================
-- RLS FIX - Safe for Existing Database
-- Fixes infinite loop issue without breaking existing data
-- ============================================================================

-- 1. ADD MISSING COLUMNS (Safe for existing tables)
-- ============================================================================

-- Add tenant_id to audit_logs if missing
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'audit_logs' AND column_name = 'tenant_id'
    ) THEN
        ALTER TABLE public.audit_logs ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
        CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant ON public.audit_logs(tenant_id);
    END IF;
END $$;

-- 2. REPLACE SECURITY FUNCTIONS (Loop-Free Version)
-- ============================================================================

-- Get current user's tenant_id (Efficient & Recursive-Safe)
CREATE OR REPLACE FUNCTION public.get_user_tenant_id()
RETURNS UUID AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  -- Try to get from JWT metadata first (fastest, no DB read)
  v_tenant_id := (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID;
  
  IF v_tenant_id IS NOT NULL THEN
    RETURN v_tenant_id;
  END IF;
  
  -- Fallback to database query (Security Definer avoids RLS loop)
  SELECT tenant_id INTO v_tenant_id FROM public.profiles WHERE id = auth.uid();
  RETURN v_tenant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Check if user is Super Admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
BEGIN
  v_role := auth.jwt() -> 'user_metadata' ->> 'role';
  IF v_role = 'SUPER_ADMIN' THEN RETURN TRUE; END IF;
  
  RETURN EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'SUPER_ADMIN');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Check if user can manage products
CREATE OR REPLACE FUNCTION public.can_manage_products()
RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
BEGIN
  v_role := auth.jwt() -> 'user_metadata' ->> 'role';
  IF v_role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager') THEN
    RETURN TRUE;
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 3. FIX PRODUCTS POLICIES (Remove Loop)
-- ============================================================================

DROP POLICY IF EXISTS "Managers create products" ON public.products;
DROP POLICY IF EXISTS "Managers update products" ON public.products;
DROP POLICY IF EXISTS "Managers delete products" ON public.products;
DROP POLICY IF EXISTS "Users view tenant products" ON public.products;
DROP POLICY IF EXISTS "Super Admin views all products" ON public.products;
DROP POLICY IF EXISTS "products_service_role" ON public.products;
DROP POLICY IF EXISTS "products_tenant_select" ON public.products;
DROP POLICY IF EXISTS "products_tenant_insert" ON public.products;
DROP POLICY IF EXISTS "products_tenant_update" ON public.products;
DROP POLICY IF EXISTS "products_tenant_delete" ON public.products;

-- Service Role (all access)
CREATE POLICY "products_service_role" ON public.products 
FOR ALL TO service_role 
USING (true) 
WITH CHECK (true);

-- Authenticated Users - View
CREATE POLICY "products_tenant_select" ON public.products 
FOR SELECT TO authenticated 
USING (
  tenant_id = public.get_user_tenant_id()
  OR 
  public.is_super_admin()
);

-- Authenticated Users - Insert
CREATE POLICY "products_tenant_insert" ON public.products 
FOR INSERT TO authenticated 
WITH CHECK (
  public.can_manage_products() 
  AND tenant_id = public.get_user_tenant_id()
);

-- Authenticated Users - Update
CREATE POLICY "products_tenant_update" ON public.products 
FOR UPDATE TO authenticated 
USING (
  public.can_manage_products() 
  AND tenant_id = public.get_user_tenant_id()
);

-- Authenticated Users - Delete
CREATE POLICY "products_tenant_delete" ON public.products 
FOR DELETE TO authenticated 
USING (
  public.can_manage_products() 
  AND tenant_id = public.get_user_tenant_id()
);

-- 4. FIX CATEGORIES POLICIES
-- ============================================================================

DROP POLICY IF EXISTS "Users view tenant categories" ON public.categories;
DROP POLICY IF EXISTS "Users manage tenant categories" ON public.categories;
DROP POLICY IF EXISTS "Super Admin views all categories" ON public.categories;
DROP POLICY IF EXISTS "categories_service_role" ON public.categories;
DROP POLICY IF EXISTS "categories_tenant_all" ON public.categories;

CREATE POLICY "categories_service_role" ON public.categories 
FOR ALL TO service_role 
USING (true) WITH CHECK (true);

CREATE POLICY "categories_tenant_all" ON public.categories 
FOR ALL TO authenticated 
USING (tenant_id = public.get_user_tenant_id() OR public.is_super_admin())
WITH CHECK (tenant_id = public.get_user_tenant_id() OR public.is_super_admin());

-- 5. FIX PROFILES POLICIES (Critical for auth)
-- ============================================================================

DROP POLICY IF EXISTS "Users view same tenant profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_read_tenant" ON public.profiles;
DROP POLICY IF EXISTS "profiles_tenant_isolation" ON public.profiles;
DROP POLICY IF EXISTS "Super Admin views all profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_service_role" ON public.profiles;
DROP POLICY IF EXISTS "profiles_self" ON public.profiles;
DROP POLICY IF EXISTS "profiles_super_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_tenant_read" ON public.profiles;

-- Service role always works
CREATE POLICY "profiles_service_role" ON public.profiles 
FOR ALL TO service_role 
USING (true) WITH CHECK (true);

-- Users read their own profile
CREATE POLICY "profiles_self" ON public.profiles 
FOR SELECT TO authenticated 
USING (id = auth.uid());

-- Super Admin sees all
CREATE POLICY "profiles_super_admin" ON public.profiles 
FOR ALL TO authenticated 
USING (public.is_super_admin())
WITH CHECK (public.is_super_admin());

-- Same tenant view (safe - no recursion now)
CREATE POLICY "profiles_tenant_read" ON public.profiles 
FOR SELECT TO authenticated 
USING (tenant_id = public.get_user_tenant_id());

-- 6. GRANTS
-- ============================================================================

GRANT ALL ON public.products TO authenticated, service_role;
GRANT ALL ON public.profiles TO authenticated, service_role;
GRANT ALL ON public.categories TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_tenant_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_products() TO authenticated, service_role;

-- 7. VERIFICATION
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ RLS Fix Applied Successfully!';
  RAISE NOTICE 'Functions updated: get_user_tenant_id, is_super_admin, can_manage_products';
  RAISE NOTICE 'Policies fixed: products, categories, profiles';
  RAISE NOTICE 'Next: Try creating a product as VENDOR_ADMIN';
END $$;
