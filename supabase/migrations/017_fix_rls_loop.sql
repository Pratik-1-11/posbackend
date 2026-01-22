
-- 1. FIX THE RLS LOOP
-- The previous get_user_tenant_id() queried profiles, which had RLS calling get_user_tenant_id().
-- We now use a more robust version that checks JWT metadata first and is SECURITY DEFINER.

CREATE OR REPLACE FUNCTION public.get_user_tenant_id()
RETURNS UUID AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  -- Try to get from JWT metadata first (fast, bypasses RLS)
  v_tenant_id := (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID;
  
  IF v_tenant_id IS NOT NULL THEN
    RETURN v_tenant_id;
  END IF;
  
  -- Fallback to database query (Security Definer handles RLS bypass)
  SELECT tenant_id INTO v_tenant_id FROM public.profiles WHERE id = auth.uid();
  RETURN v_tenant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 2. FIX can_manage_products loop
CREATE OR REPLACE FUNCTION public.can_manage_products()
RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
BEGIN
  -- Try JWT first
  v_role := auth.jwt() -> 'user_metadata' ->> 'role';
  
  IF v_role IS NOT NULL THEN
    RETURN v_role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager');
  END IF;

  -- Fallback to database
  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 3. RESET POLICIES FOR PRODUCTS
DROP POLICY IF EXISTS "Managers create products" ON public.products;
DROP POLICY IF EXISTS "products_service_role" ON public.products;
DROP POLICY IF EXISTS "products_tenant_select" ON public.products;
DROP POLICY IF EXISTS "Users view tenant products" ON public.products;
DROP POLICY IF EXISTS "Super Admin views all products" ON public.products;

-- Service Role (all access)
CREATE POLICY "products_service_role" ON public.products FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Authenticated Users (Isolation)
CREATE POLICY "products_tenant_select" ON public.products FOR SELECT TO authenticated 
USING (
  tenant_id = public.get_user_tenant_id()
  OR 
  (auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN'
);

CREATE POLICY "products_tenant_insert" ON public.products FOR INSERT TO authenticated 
WITH CHECK (
  public.can_manage_products() AND
  tenant_id = public.get_user_tenant_id()
);

CREATE POLICY "products_tenant_update" ON public.products FOR UPDATE TO authenticated 
USING (
  public.can_manage_products() AND
  tenant_id = public.get_user_tenant_id()
);

-- 4. FIX PROFILES POLICIES
DROP POLICY IF EXISTS "Users view same tenant profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_read_tenant" ON public.profiles;

CREATE POLICY "profiles_tenant_isolation" ON public.profiles FOR SELECT TO authenticated
USING (
  tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::UUID
  OR
  (SELECT p.tenant_id FROM public.profiles p WHERE p.id = auth.uid()) = tenant_id
);

-- 5. GRANTS
GRANT ALL ON public.products TO authenticated, service_role;
GRANT ALL ON public.profiles TO authenticated, service_role;
GRANT ALL ON public.categories TO authenticated, service_role;
