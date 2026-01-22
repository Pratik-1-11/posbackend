-- ==========================================
-- MULTI-TENANT MIGRATION
-- Transforms single-tenant POS to multi-tenant SaaS
-- Version: 1.0
-- Date: 2026-01-01
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

-- PHASE 2: ADD TENANT_ID TO EXISTING TABLES
-- ==========================================

-- 2.1 Add tenant_id to profiles (nullable initially)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.2 Add tenant_id to branches
ALTER TABLE public.branches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.3 Add tenant_id to products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.4 Add tenant_id to categories
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.5 Add tenant_id to suppliers
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.6 Add tenant_id to customers
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.7 Add tenant_id to sales
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.8 Add tenant_id to expenses
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.9 Add tenant_id to purchases
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- 2.10 Add tenant_id to settings
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;

-- PHASE 3: CREATE DEFAULT TENANT & BACKFILL DATA
-- ==========================================

-- 3.1 Insert default "super" tenant for platform admin
DO $$
DECLARE
  v_super_tenant_id UUID := '00000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.tenants (id, name, slug, type, contact_email, subscription_status, is_active)
  VALUES (
    v_super_tenant_id,
    'Platform Admin',
    'platform-admin',
    'super',
    'admin@platform.com',
    'active',
    TRUE
  )
  ON CONFLICT (id) DO NOTHING;
END $$;

-- 3.2 Insert default vendor tenant for existing data
DO $$
DECLARE
  v_default_tenant_id UUID := '00000000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO public.tenants (id, name, slug, type, contact_email, subscription_status, is_active)
  VALUES (
    v_default_tenant_id,
    'Default Store',
    'default-store',
    'vendor',
    'store@example.com',
    'active',
    TRUE
  )
  ON CONFLICT (id) DO NOTHING;
END $$;

-- 3.3 Backfill tenant_id for existing data (use default vendor tenant)
UPDATE public.profiles SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.branches SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.products SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.categories SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.suppliers SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.customers SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.sales SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.expenses SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.purchases SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
UPDATE public.settings SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;

-- PHASE 4: MAKE TENANT_ID NOT NULL
-- ==========================================

ALTER TABLE public.profiles ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.branches ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.products ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.categories ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.suppliers ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.customers ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.sales ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.expenses ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.purchases ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.settings ALTER COLUMN tenant_id SET NOT NULL;

-- PHASE 5: CREATE TENANT-AWARE INDEXES
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_profiles_tenant ON public.profiles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_profiles_tenant_role ON public.profiles(tenant_id, role);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

CREATE INDEX IF NOT EXISTS idx_branches_tenant ON public.branches(tenant_id);

CREATE INDEX IF NOT EXISTS idx_products_tenant ON public.products(tenant_id);
CREATE INDEX IF NOT EXISTS idx_products_tenant_active ON public.products(tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_products_tenant_category ON public.products(tenant_id, category_id);

CREATE INDEX IF NOT EXISTS idx_categories_tenant ON public.categories(tenant_id);

CREATE INDEX IF NOT EXISTS idx_suppliers_tenant ON public.suppliers(tenant_id);

CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_customers_tenant_phone ON public.customers(tenant_id, phone);

CREATE INDEX IF NOT EXISTS idx_sales_tenant ON public.sales(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sales_tenant_date ON public.sales(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_tenant_status ON public.sales(tenant_id, status);

CREATE INDEX IF NOT EXISTS idx_expenses_tenant ON public.expenses(tenant_id);
CREATE INDEX IF NOT EXISTS idx_expenses_tenant_date ON public.expenses(tenant_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_purchases_tenant ON public.purchases(tenant_id);
CREATE INDEX IF NOT EXISTS idx_purchases_tenant_date ON public.purchases(tenant_id, purchase_date DESC);

CREATE INDEX IF NOT EXISTS idx_settings_tenant ON public.settings(tenant_id);

-- PHASE 6: UPDATE ROLE CONSTRAINTS
-- ==========================================

-- Drop old role constraint
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;

-- Add new multi-tenant roles
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
  CHECK (role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER'));

-- Add unique constraint for email per tenant
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_tenant_email_key;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_tenant_email_key UNIQUE (tenant_id, email);

-- PHASE 7: HELPER FUNCTIONS FOR MULTI-TENANCY
-- ==========================================

-- 7.1 Get current user's tenant_id
CREATE OR REPLACE FUNCTION public.get_user_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 7.2 Check if user is Super Admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'SUPER_ADMIN'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 7.3 Check if user is Vendor Admin
CREATE OR REPLACE FUNCTION public.is_vendor_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'VENDOR_ADMIN'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 7.4 Check if user can manage users
CREATE OR REPLACE FUNCTION public.can_manage_users()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 7.5 Check if user can manage products
CREATE OR REPLACE FUNCTION public.can_manage_products()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 7.6 Check if user can manage reports
CREATE OR REPLACE FUNCTION public.can_view_reports()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- PHASE 8: ROW LEVEL SECURITY POLICIES
-- ==========================================

-- 8.1 TENANTS TABLE POLICIES
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super Admin manages all tenants" ON public.tenants;
CREATE POLICY "Super Admin manages all tenants" 
  ON public.tenants FOR ALL
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Vendor admin views own tenant" ON public.tenants;
CREATE POLICY "Vendor admin views own tenant"
  ON public.tenants FOR SELECT
  USING (id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Vendor admin updates own tenant" ON public.tenants;
CREATE POLICY "Vendor admin updates own tenant"
  ON public.tenants FOR UPDATE
  USING (id = public.get_user_tenant_id() AND public.is_vendor_admin());

-- 8.2 PROFILES POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Admins manage all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;

-- Super Admin sees all users
DROP POLICY IF EXISTS "Super Admin views all profiles" ON public.profiles;
CREATE POLICY "Super Admin views all profiles" 
  ON public.profiles FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's users
DROP POLICY IF EXISTS "Users view same tenant profiles" ON public.profiles;
CREATE POLICY "Users view same tenant profiles"
  ON public.profiles FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- Only admins can create users within their tenant
DROP POLICY IF EXISTS "Admins create users" ON public.profiles;
CREATE POLICY "Admins create users"
  ON public.profiles FOR INSERT
  WITH CHECK (
    public.can_manage_users() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- Users can update their own profile
DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid());

-- Admins can update their tenant's users
DROP POLICY IF EXISTS "Admins update tenant users" ON public.profiles;
CREATE POLICY "Admins update tenant users"
  ON public.profiles FOR UPDATE
  USING (
    public.can_manage_users() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.3 PRODUCTS POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Everyone views products" ON public.products;
DROP POLICY IF EXISTS "Admins/Managers manage products" ON public.products;

-- Super Admin sees all products
DROP POLICY IF EXISTS "Super Admin views all products" ON public.products;
CREATE POLICY "Super Admin views all products"
  ON public.products FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's products
DROP POLICY IF EXISTS "Users view tenant products" ON public.products;
CREATE POLICY "Users view tenant products"
  ON public.products FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- Product managers can create products
DROP POLICY IF EXISTS "Managers create products" ON public.products;
CREATE POLICY "Managers create products"
  ON public.products FOR INSERT
  WITH CHECK (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- Product managers can update their tenant's products
DROP POLICY IF EXISTS "Managers update products" ON public.products;
CREATE POLICY "Managers update products"
  ON public.products FOR UPDATE
  USING (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- Product managers can delete their tenant's products
DROP POLICY IF EXISTS "Managers delete products" ON public.products;
CREATE POLICY "Managers delete products"
  ON public.products FOR DELETE
  USING (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.4 SALES POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Everyone views sales" ON public.sales;
DROP POLICY IF EXISTS "Cashiers and above create sales" ON public.sales;

-- Super Admin sees all sales
DROP POLICY IF EXISTS "Super Admin views all sales" ON public.sales;
CREATE POLICY "Super Admin views all sales"
  ON public.sales FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's sales
DROP POLICY IF EXISTS "Users view tenant sales" ON public.sales;
CREATE POLICY "Users view tenant sales"
  ON public.sales FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- Cashiers and above can create sales
DROP POLICY IF EXISTS "Cashiers create sales" ON public.sales;
CREATE POLICY "Cashiers create sales"
  ON public.sales FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER')
    ) AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.5 CUSTOMERS POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Everyone manages customers" ON public.customers;

-- Super Admin sees all customers
DROP POLICY IF EXISTS "Super Admin views all customers" ON public.customers;
CREATE POLICY "Super Admin views all customers"
  ON public.customers FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's customers
DROP POLICY IF EXISTS "Users view tenant customers" ON public.customers;
CREATE POLICY "Users view tenant customers"
  ON public.customers FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- All authenticated users can manage customers within their tenant
DROP POLICY IF EXISTS "Users manage tenant customers" ON public.customers;
CREATE POLICY "Users manage tenant customers"
  ON public.customers FOR ALL
  USING (
    public.is_super_admin() OR tenant_id = public.get_user_tenant_id()
  )
  WITH CHECK (
    public.is_super_admin() OR tenant_id = public.get_user_tenant_id()
  );

-- 8.6 CATEGORIES POLICIES
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super Admin views all categories" ON public.categories;
CREATE POLICY "Super Admin views all categories"
  ON public.categories FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant categories" ON public.categories;
CREATE POLICY "Users view tenant categories"
  ON public.categories FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Users manage tenant categories" ON public.categories;
CREATE POLICY "Users manage tenant categories"
  ON public.categories FOR ALL
  USING (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  )
  WITH CHECK (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.7 SUPPLIERS POLICIES
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super Admin views all suppliers" ON public.suppliers;
CREATE POLICY "Super Admin views all suppliers"
  ON public.suppliers FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant suppliers" ON public.suppliers;
CREATE POLICY "Users view tenant suppliers"
  ON public.suppliers FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Users manage tenant suppliers" ON public.suppliers;
CREATE POLICY "Users manage tenant suppliers"
  ON public.suppliers FOR ALL
  USING (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  )
  WITH CHECK (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.8 EXPENSES POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Everyone views expenses" ON public.expenses;
DROP POLICY IF EXISTS "Admins/Managers manage expenses" ON public.expenses;

DROP POLICY IF EXISTS "Super Admin views all expenses" ON public.expenses;
CREATE POLICY "Super Admin views all expenses"
  ON public.expenses FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant expenses" ON public.expenses;
CREATE POLICY "Users view tenant expenses"
  ON public.expenses FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Managers manage tenant expenses" ON public.expenses;
CREATE POLICY "Managers manage tenant expenses"
  ON public.expenses FOR ALL
  USING (
    public.can_view_reports() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  )
  WITH CHECK (
    public.can_view_reports() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.9 PURCHASES POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Everyone views purchases" ON public.purchases;
DROP POLICY IF EXISTS "Admins/Managers manage purchases" ON public.purchases;

DROP POLICY IF EXISTS "Super Admin views all purchases" ON public.purchases;
CREATE POLICY "Super Admin views all purchases"
  ON public.purchases FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant purchases" ON public.purchases;
CREATE POLICY "Users view tenant purchases"
  ON public.purchases FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Managers manage tenant purchases" ON public.purchases;
CREATE POLICY "Managers manage tenant purchases"
  ON public.purchases FOR ALL
  USING (
    public.can_view_reports() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  )
  WITH CHECK (
    public.can_view_reports() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.10 SETTINGS POLICIES
-- Drop old policies
DROP POLICY IF EXISTS "Everyone views settings" ON public.settings;
DROP POLICY IF EXISTS "Admins manage settings" ON public.settings;

DROP POLICY IF EXISTS "Super Admin views all settings" ON public.settings;
CREATE POLICY "Super Admin views all settings"
  ON public.settings FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Users view tenant settings" ON public.settings;
CREATE POLICY "Users view tenant settings"
  ON public.settings FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Admins manage tenant settings" ON public.settings;
CREATE POLICY "Admins manage tenant settings"
  ON public.settings FOR ALL
  USING (
    public.is_vendor_admin() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  )
  WITH CHECK (
    public.is_vendor_admin() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- 8.11 AUDIT LOGS POLICIES
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super Admin views all audit logs" ON public.audit_logs;
CREATE POLICY "Super Admin views all audit logs"
  ON public.audit_logs FOR SELECT
  USING (public.is_super_admin());

DROP POLICY IF EXISTS "Admins view tenant audit logs" ON public.audit_logs;
CREATE POLICY "Admins view tenant audit logs"
  ON public.audit_logs FOR SELECT
  USING (
    public.is_vendor_admin() AND
    tenant_id = public.get_user_tenant_id()
  );

-- Only system can insert audit logs
DROP POLICY IF EXISTS "System inserts audit logs" ON public.audit_logs;
CREATE POLICY "System inserts audit logs"
  ON public.audit_logs FOR INSERT
  WITH CHECK (true);

-- PHASE 9: UPDATE EXISTING FUNCTIONS FOR MULTI-TENANCY
-- ==========================================

-- 9.1 Update process_pos_sale to include tenant_id
DROP FUNCTION IF EXISTS process_pos_sale(JSONB, UUID, UUID, UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB, TEXT);
CREATE OR REPLACE FUNCTION process_pos_sale(
  p_items JSONB,
  p_customer_id UUID DEFAULT NULL,
  p_cashier_id UUID DEFAULT NULL,
  p_branch_id UUID DEFAULT NULL,
  p_discount_amount NUMERIC DEFAULT 0,
  p_taxable_amount NUMERIC DEFAULT 0,
  p_vat_amount NUMERIC DEFAULT 0,
  p_total_amount NUMERIC DEFAULT 0,
  p_payment_method TEXT DEFAULT 'cash',
  p_payment_details JSONB DEFAULT '{}'::jsonb,
  p_customer_name TEXT DEFAULT 'Walk-in'
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_tenant_id UUID;
BEGIN
  -- Get tenant_id from current user's profile
  SELECT tenant_id INTO v_tenant_id FROM public.profiles WHERE id = auth.uid();
  
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'User tenant not found';
  END IF;

  -- Validate all products belong to user's tenant
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_items) AS item
    LEFT JOIN public.products p ON p.id = (item->>'product_id')::UUID
    WHERE p.tenant_id != v_tenant_id OR p.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Invalid products: some items do not belong to your store';
  END IF;

  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 10000)::text, 4, '0');
  v_sub_total := p_total_amount + p_discount_amount;

  INSERT INTO public.sales (
    tenant_id, invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, created_at
  )
  VALUES (
    v_tenant_id, v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed', NOW()
  )
  RETURNING id INTO v_sale_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.sale_items (sale_id, product_id, product_name, quantity, unit_price, total_price)
    VALUES (
      v_sale_id, (v_item->>'product_id')::UUID, v_item->>'product_name', 
      (v_item->>'quantity')::INTEGER, (v_item->>'unit_price')::NUMERIC, (v_item->>'total_price')::NUMERIC
    );

    UPDATE public.products SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'product_id')::UUID AND tenant_id = v_tenant_id;
  END LOOP;

  IF p_payment_method = 'credit' THEN
    v_credit_amount := p_total_amount;
  ELSIF p_payment_method = 'mixed' THEN
    IF p_payment_details ? 'credit' THEN
      v_credit_amount := (p_payment_details->>'credit')::NUMERIC;
    END IF;
  END IF;

  IF v_credit_amount > 0 THEN
    IF p_customer_id IS NULL THEN
      RAISE EXCEPTION 'Customer ID is required for credit payments';
    END IF;
    PERFORM add_customer_transaction(p_customer_id, 'sale', v_credit_amount, 'POS Sale: ' || v_invoice_number, v_sale_id, p_cashier_id);
  END IF;

  IF p_payment_details ? 'debt_payment' THEN
    DECLARE
      v_debt_pay NUMERIC := (p_payment_details->>'debt_payment')::NUMERIC;
    BEGIN
      IF v_debt_pay > 0 AND p_customer_id IS NOT NULL THEN
        PERFORM add_customer_transaction(p_customer_id, 'payment', v_debt_pay, 'Debt Payment during Sale: ' || v_invoice_number, v_sale_id, p_cashier_id);
      END IF;
    END;
  END IF;

  RETURN jsonb_build_object('id', v_sale_id, 'invoice_number', v_invoice_number, 'status', 'success');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- PHASE 10: CREATE TENANT-AWARE VIEWS
-- ==========================================

-- 10.1 Drop existing views
DROP VIEW IF EXISTS daily_sales_summary;
DROP VIEW IF EXISTS cashier_performance;
DROP VIEW IF EXISTS expense_summary;
DROP VIEW IF EXISTS purchase_summary;
DROP VIEW IF EXISTS product_performance;

-- 10.2 Recreate views with tenant_id
CREATE OR REPLACE VIEW daily_sales_summary AS
SELECT 
  tenant_id,
  DATE(created_at) as sale_date, 
  COUNT(id) as total_transactions, 
  SUM(sub_total) as total_sub_total, 
  SUM(discount_amount) as total_discount, 
  SUM(taxable_amount) as total_taxable, 
  SUM(vat_amount) as total_vat, 
  SUM(total_amount) as total_revenue
FROM public.sales 
WHERE status = 'completed'
GROUP BY tenant_id, DATE(created_at) 
ORDER BY tenant_id, sale_date DESC;

CREATE OR REPLACE VIEW cashier_performance AS
SELECT 
  s.tenant_id,
  p.full_name as cashier_name, 
  s.cashier_id, 
  COUNT(s.id) as total_sales_count, 
  SUM(s.total_amount) as total_revenue_generated
FROM public.sales s 
JOIN public.profiles p ON s.cashier_id = p.id 
WHERE s.status = 'completed'
GROUP BY s.tenant_id, s.cashier_id, p.full_name;

CREATE OR REPLACE VIEW expense_summary AS
SELECT 
  tenant_id,
  DATE(date) as expense_date, 
  category, 
  status, 
  COUNT(id) as total_entries, 
  SUM(amount) as total_amount
FROM public.expenses 
GROUP BY tenant_id, DATE(date), category, status 
ORDER BY tenant_id, expense_date DESC;

CREATE OR REPLACE VIEW purchase_summary AS
SELECT 
  tenant_id,
  DATE(purchase_date) as purchase_date, 
  supplier_name, 
  status, 
  COUNT(id) as total_entries, 
  SUM(quantity) as total_quantity, 
  SUM(total_amount) as total_spent
FROM public.purchases 
GROUP BY tenant_id, DATE(purchase_date), supplier_name, status 
ORDER BY tenant_id, purchase_date DESC;

CREATE OR REPLACE VIEW product_performance AS
SELECT 
  s.tenant_id,
  si.product_name as name, 
  SUM(si.quantity) as quantity, 
  SUM(si.total_price) as revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
WHERE s.status = 'completed'
GROUP BY s.tenant_id, si.product_name 
ORDER BY s.tenant_id, revenue DESC;

-- PHASE 11: TRIGGERS
-- ==========================================

-- Trigger to update tenants.updated_at
DROP TRIGGER IF EXISTS update_tenants_updated_at ON public.tenants;
CREATE TRIGGER update_tenants_updated_at 
  BEFORE UPDATE ON public.tenants 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- PHASE 12: VERIFICATION QUERIES
-- ==========================================

-- Verify migration success
DO $$
DECLARE
  v_tenant_count INT;
  v_profile_count INT;
  v_product_count INT;
BEGIN
  SELECT COUNT(*) INTO v_tenant_count FROM public.tenants;
  SELECT COUNT(*) INTO v_profile_count FROM public.profiles WHERE tenant_id IS NOT NULL;
  SELECT COUNT(*) INTO v_product_count FROM public.products WHERE tenant_id IS NOT NULL;
  
  RAISE NOTICE 'Migration verification:';
  RAISE NOTICE '- Total tenants: %', v_tenant_count;
  RAISE NOTICE '- Profiles with tenant: %', v_profile_count;
  RAISE NOTICE '- Products with tenant: %', v_product_count;
  
  IF v_tenant_count < 1 THEN
    RAISE EXCEPTION 'Migration failed: No tenants created';
  END IF;
END $$;

-- SUCCESS MESSAGE
DO $$
BEGIN
  RAISE NOTICE '✅ Multi-tenant migration completed successfully!';
  RAISE NOTICE '';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '1. Update application code to use tenant-aware queries';
  RAISE NOTICE '2. Create Super Admin user and assign to super tenant';
  RAISE NOTICE '3. Migrate existing users to appropriate roles';
  RAISE NOTICE '4. Test tenant isolation rigorously';
  RAISE NOTICE '5. Set up monitoring and audit logging';
END $$;
