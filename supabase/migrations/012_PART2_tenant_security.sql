-- ==========================================
-- PART 2: ADD MULTI-TENANT FUNCTIONS & RLS
-- Run this AFTER Part 1 (column addition) succeeds
-- This adds the security and helper functions
-- ==========================================

-- PHASE 1: HELPER FUNCTIONS FOR MULTI-TENANCY
-- ==========================================

-- Get current user's tenant_id
CREATE OR REPLACE FUNCTION public.get_user_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user is Super Admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'SUPER_ADMIN'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user is Vendor Admin
CREATE OR REPLACE FUNCTION public.is_vendor_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('VENDOR_ADMIN', 'admin')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user can manage products
CREATE OR REPLACE FUNCTION public.can_manage_products()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- PHASE 2: UPDATE ROLE CONSTRAINTS
-- ==========================================

-- Allow both new and old role names during transition
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
  CHECK (role IN (
    'SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER',
    'super_admin', 'branch_admin', 'cashier', 'inventory_manager', 'waiter', 'manager', 'admin'
  ));

-- PHASE 3: ADD FOREIGN KEY CONSTRAINTS
-- ==========================================

-- Add foreign key constraints to ensure data integrity
ALTER TABLE public.profiles 
  DROP CONSTRAINT IF EXISTS profiles_tenant_id_fkey,
  ADD CONSTRAINT profiles_tenant_id_fkey 
  FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;

ALTER TABLE public.products 
  DROP CONSTRAINT IF EXISTS products_tenant_id_fkey,
  ADD CONSTRAINT products_tenant_id_fkey 
  FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;

ALTER TABLE public.customers 
  DROP CONSTRAINT IF EXISTS customers_tenant_id_fkey,
  ADD CONSTRAINT customers_tenant_id_fkey 
  FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;

ALTER TABLE public.sales 
  DROP CONSTRAINT IF EXISTS sales_tenant_id_fkey,
  ADD CONSTRAINT sales_tenant_id_fkey 
  FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;

-- PHASE 4: MAKE TENANT_ID NOT NULL (Important for data integrity)
-- ==========================================

-- This ensures all future records MUST have a tenant_id
ALTER TABLE public.profiles ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.products ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.customers ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.sales ALTER COLUMN tenant_id SET NOT NULL;

-- PHASE 5: CREATE INDEXES FOR PERFORMANCE
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_profiles_tenant ON public.profiles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_profiles_tenant_role ON public.profiles(tenant_id, role);

CREATE INDEX IF NOT EXISTS idx_products_tenant ON public.products(tenant_id);
CREATE INDEX IF NOT EXISTS idx_products_tenant_active ON public.products(tenant_id, is_active);

CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers(tenant_id);

CREATE INDEX IF NOT EXISTS idx_sales_tenant ON public.sales(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sales_tenant_date ON public.sales(tenant_id, created_at DESC);

-- PHASE 6: ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================

-- Enable RLS on all multi-tenant tables
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

-- TENANTS TABLE POLICIES
DROP POLICY IF EXISTS "Super Admin manages all tenants" ON public.tenants;
CREATE POLICY "Super Admin manages all tenants" 
  ON public.tenants FOR ALL
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view own tenant" ON public.tenants;
CREATE POLICY "Users view own tenant"
  ON public.tenants FOR SELECT
  USING (id = public.get_user_tenant_id());

-- PROFILES POLICIES
DROP POLICY IF EXISTS "Super Admin views all profiles" ON public.profiles;
CREATE POLICY "Super Admin views all profiles" 
  ON public.profiles FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view same tenant profiles" ON public.profiles;
CREATE POLICY "Users view same tenant profiles"
  ON public.profiles FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid());

-- PRODUCTS POLICIES
DROP POLICY IF EXISTS "Super Admin views all products" ON public.products;
CREATE POLICY "Super Admin views all products"
  ON public.products FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant products" ON public.products;
CREATE POLICY "Users view tenant products"
  ON public.products FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Managers create products" ON public.products;
CREATE POLICY "Managers create products"
  ON public.products FOR INSERT
  WITH CHECK (
    public.can_manage_products() AND
    tenant_id = public.get_user_tenant_id()
  );

DROP POLICY IF EXISTS "Managers update products" ON public.products;
CREATE POLICY "Managers update products"
  ON public.products FOR UPDATE
  USING (
    public.can_manage_products() AND
    tenant_id = public.get_user_tenant_id()
  );

-- CUSTOMERS POLICIES
DROP POLICY IF EXISTS "Super Admin views all customers" ON public.customers;
CREATE POLICY "Super Admin views all customers"
  ON public.customers FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant customers" ON public.customers;
CREATE POLICY "Users view tenant customers"
  ON public.customers FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Users manage tenant customers" ON public.customers;
CREATE POLICY "Users manage tenant customers"
  ON public.customers FOR ALL
  USING (tenant_id = public.get_user_tenant_id())
  WITH CHECK (tenant_id = public.get_user_tenant_id());

-- SALES POLICIES
DROP POLICY IF EXISTS "Super Admin views all sales" ON public.sales;
CREATE POLICY "Super Admin views all sales"
  ON public.sales FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant sales" ON public.sales;
CREATE POLICY "Users view tenant sales"
  ON public.sales FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Cashiers create sales" ON public.sales;
CREATE POLICY "Cashiers create sales"
  ON public.sales FOR INSERT
  WITH CHECK (tenant_id = public.get_user_tenant_id());

-- SUCCESS MESSAGE
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '==========================================';
  RAISE NOTICE '✅ PART 2 COMPLETED SUCCESSFULLY!';
  RAISE NOTICE '✅ Multi-Tenant Security Enabled!';
  RAISE NOTICE '==========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'What was added:';
  RAISE NOTICE '✅ Helper functions (get_user_tenant_id, is_super_admin, etc.)';
  RAISE NOTICE '✅ Foreign key constraints';
  RAISE NOTICE '✅ NOT NULL constraints on tenant_id';
  RAISE NOTICE '✅ Performance indexes';
  RAISE NOTICE '✅ Row-Level Security (RLS) policies';
  RAISE NOTICE '';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '1. Make yourself Super Admin';
  RAISE NOTICE '2. Update backend code to use tenant middleware';
  RAISE NOTICE '3. Test with different user roles';
  RAISE NOTICE '';
END $$;
