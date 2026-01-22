-- ============================================================================
-- CONSOLIDATED MULTI-TENANT POS SCHEMA
-- Version: 2.0 (Stable & Secure)
-- Description: Single file containing full schema with fixed loop-free RLS
-- ============================================================================

-- 1. INFRASTRUCTURE & EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Helper for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. CORE IDENTITY TABLES
-- ============================================================================

-- 2.1 Tenants (SaaS Accounts)
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  type TEXT NOT NULL DEFAULT 'vendor' CHECK (type IN ('super', 'vendor')),
  business_name TEXT,
  contact_email TEXT NOT NULL,
  contact_phone TEXT,
  address TEXT,
  subscription_tier TEXT DEFAULT 'basic' CHECK (subscription_tier IN ('basic', 'pro', 'enterprise')),
  subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'trial', 'suspended', 'cancelled')),
  settings JSONB DEFAULT '{}'::jsonb,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.2 Branches (Locations within a Tenant)
CREATE TABLE IF NOT EXISTS public.branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  location TEXT,
  contact_number TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2.3 Profiles (Extended User Data)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  username TEXT,
  email TEXT,
  full_name TEXT,
  role TEXT NOT NULL CHECK (role IN (
    'SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER',
    'super_admin', 'branch_admin', 'cashier', 'inventory_manager', 'waiter', 'manager', 'admin'
  )),
  branch_id UUID REFERENCES public.branches(id),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. INVENTORY SYSTEM
-- ============================================================================

-- 3.1 Categories
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.2 Suppliers
CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3.3 Products
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  barcode TEXT,
  description TEXT,
  category_id UUID REFERENCES public.categories(id),
  supplier_id UUID REFERENCES public.suppliers(id),
  cost_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
  selling_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  min_stock_level INTEGER DEFAULT 5,
  is_active BOOLEAN DEFAULT TRUE,
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, barcode) -- Barcode unique per tenant
);

-- 4. SALES & CUSTOMERS
-- ============================================================================

-- 4.1 Customers
CREATE TABLE IF NOT EXISTS public.customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  email TEXT,
  address TEXT,
  total_credit NUMERIC(10, 2) DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4.2 Sales (Orders)
CREATE TABLE IF NOT EXISTS public.sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  invoice_number TEXT NOT NULL,
  cashier_id UUID REFERENCES public.profiles(id),
  branch_id UUID REFERENCES public.branches(id),
  customer_id UUID REFERENCES public.customers(id),
  customer_name TEXT DEFAULT 'Walk-in',
  payment_method TEXT CHECK (payment_method IN ('cash', 'card', 'qr', 'mixed', 'credit')),
  payment_details JSONB DEFAULT '{}'::jsonb,
  sub_total NUMERIC(10, 2) NOT NULL,
  discount_amount NUMERIC(10, 2) DEFAULT 0,
  taxable_amount NUMERIC(10, 2) NOT NULL,
  vat_amount NUMERIC(10, 2) NOT NULL,
  total_amount NUMERIC(10, 2) NOT NULL,
  status TEXT DEFAULT 'completed' CHECK (status IN ('completed', 'cancelled', 'refunded')),
  idempotency_key TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, invoice_number)
);

-- 4.3 Sale Items
CREATE TABLE IF NOT EXISTS public.sale_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.products(id),
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price NUMERIC(10, 2) NOT NULL,
  total_price NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. FINANCIALS
-- ============================================================================

-- 5.1 Expenses
CREATE TABLE IF NOT EXISTS public.expenses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  amount NUMERIC(10, 2) NOT NULL,
  category TEXT NOT NULL,
  date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  payment_method TEXT,
  receipt_url TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5.2 Purchases
CREATE TABLE IF NOT EXISTS public.purchases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  product_name TEXT NOT NULL,
  supplier_name TEXT NOT NULL,
  sku TEXT,
  quantity INTEGER NOT NULL,
  unit_price NUMERIC(10, 2) NOT NULL,
  total_amount NUMERIC(10, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  purchase_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5.3 Customer Ledger (Transactions)
CREATE TABLE IF NOT EXISTS public.customer_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  type TEXT CHECK (type IN ('opening_balance', 'sale', 'payment', 'refund', 'adjustment')),
  amount NUMERIC(10, 2) NOT NULL,
  description TEXT,
  reference_id UUID,
  performed_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. SYSTEM LOGS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES auth.users(id),
  actor_role TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  changes JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. SECURITY FUNCTIONS (Loop-Free Version)
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
BEGIN
  RETURN (auth.jwt() -> 'user_metadata' ->> 'role') = 'SUPER_ADMIN' 
     OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'SUPER_ADMIN');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Check if user can manage products
CREATE OR REPLACE FUNCTION public.can_manage_products()
RETURNS BOOLEAN AS $$
DECLARE
  v_role TEXT;
BEGIN
  v_role := auth.jwt() -> 'user_metadata' ->> 'role';
  IF v_role IS NOT NULL THEN
    RETURN v_role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager');
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 8. BUSINESS FUNCTIONS (RPC)
-- ============================================================================

-- Atomic Credit Management
CREATE OR REPLACE FUNCTION add_customer_transaction(
  p_customer_id UUID,
  p_type TEXT,
  p_amount NUMERIC,
  p_description TEXT,
  p_reference_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS UUID AS $$
DECLARE
  v_transaction_id UUID;
  v_tenant_id UUID;
BEGIN
  -- Security: Get tenant from caller context
  v_tenant_id := public.get_user_tenant_id();

  -- Insert Transaction
  INSERT INTO public.customer_transactions (tenant_id, customer_id, type, amount, description, reference_id, performed_by)
  VALUES (v_tenant_id, p_customer_id, p_type, p_amount, p_description, p_reference_id, p_user_id)
  RETURNING id INTO v_transaction_id;

  -- Update Balance
  IF p_type IN ('sale', 'opening_balance', 'adjustment') THEN
    UPDATE public.customers SET total_credit = total_credit + p_amount WHERE id = p_customer_id;
  ELSIF p_type IN ('payment', 'refund') THEN
    UPDATE public.customers SET total_credit = total_credit - p_amount WHERE id = p_customer_id;
  END IF;

  RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Secure Atomic POS Sale
CREATE OR REPLACE FUNCTION public.process_pos_sale(
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
  p_customer_name TEXT DEFAULT 'Walk-in',
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_sale_id UUID;
  v_invoice_number TEXT;
  v_item JSONB;
  v_credit_amount NUMERIC := 0;
  v_sub_total NUMERIC := 0;
  v_tenant_id UUID;
  v_prod_tenant UUID;
BEGIN
  -- 1. Security Context
  v_tenant_id := public.get_user_tenant_id();
  IF v_tenant_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Tenant not found'; END IF;

  -- 2. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.sales WHERE idempotency_key = p_idempotency_key AND tenant_id = v_tenant_id) THEN
      RETURN (SELECT jsonb_build_object('id', id, 'invoice_number', invoice_number, 'status', 'duplicate') 
              FROM public.sales WHERE idempotency_key = p_idempotency_key);
    END IF;
  END IF;

  -- 3. Generation
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 1000000)::text, 6, '0');
  v_sub_total := p_total_amount + p_discount_amount;

  -- 4. Insert Sale
  INSERT INTO public.sales (
    tenant_id, invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, idempotency_key
  ) VALUES (
    v_tenant_id, v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
    p_payment_method, p_payment_details, v_sub_total, p_discount_amount,
    p_taxable_amount, p_vat_amount, p_total_amount, 'completed', p_idempotency_key
  ) RETURNING id INTO v_sale_id;

  -- 5. Process Items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- Cross-tenant guard
    SELECT tenant_id INTO v_prod_tenant FROM public.products WHERE id = (v_item->>'product_id')::UUID;
    IF v_prod_tenant != v_tenant_id THEN RAISE EXCEPTION 'Security Error: Cross-tenant product access'; END IF;

    INSERT INTO public.sale_items (tenant_id, sale_id, product_id, product_name, quantity, unit_price, total_price)
    VALUES (v_tenant_id, v_sale_id, (v_item->>'product_id')::UUID, v_item->>'product_name', 
            (v_item->>'quantity')::INTEGER, (v_item->>'unit_price')::NUMERIC, (v_item->>'total_price')::NUMERIC);

    UPDATE public.products SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
    WHERE id = (v_item->>'product_id')::UUID;
  END LOOP;

  -- 6. Customer Credit
  IF p_payment_method = 'credit' OR (p_payment_method = 'mixed' AND p_payment_details ? 'credit') THEN
     v_credit_amount := CASE WHEN p_payment_method = 'credit' THEN p_total_amount ELSE (p_payment_details->>'credit')::NUMERIC END;
     PERFORM add_customer_transaction(p_customer_id, 'sale', v_credit_amount, 'Sale: ' || v_invoice_number, v_sale_id, p_cashier_id);
  END IF;

  RETURN jsonb_build_object('id', v_sale_id, 'invoice_number', v_invoice_number, 'status', 'success');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Clean start
DO $$
DECLARE pol record;
BEGIN
    FOR pol IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') 
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename); END LOOP;
END $$;

-- Policies Implementation
CREATE POLICY "service_role_all" ON public.profiles FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "super_admin_all" ON public.profiles FOR ALL TO authenticated USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

-- Standard Tenant Isolation (Applying to all tenant-aware tables)
-- Tables: branches, categories, suppliers, products, customers, sales, sale_items, expenses, purchases, customer_transactions, audit_logs

DO $$
DECLARE 
    t_name text;
    tables text[] := ARRAY['branches', 'categories', 'suppliers', 'products', 'customers', 'sales', 'sale_items', 'expenses', 'purchases', 'customer_transactions', 'audit_logs', 'profiles'];
BEGIN
    FOREACH t_name IN ARRAY tables LOOP
        EXECUTE format('CREATE POLICY %I_isolation ON public.%I FOR ALL TO authenticated USING (tenant_id = public.get_user_tenant_id()) WITH CHECK (tenant_id = public.get_user_tenant_id())', t_name, t_name);
    END LOOP;
END $$;

-- Specific overrides
CREATE POLICY "profiles_self_read" ON public.profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "tenants_own_read" ON public.tenants FOR SELECT USING (id = public.get_user_tenant_id());

-- 10. VIEWS (Tenant-Aware)
-- ============================================================================

CREATE OR REPLACE VIEW daily_sales_summary AS
SELECT tenant_id, DATE(created_at) as sale_date, COUNT(id) as total_transactions, SUM(total_amount) as total_revenue
FROM public.sales WHERE status = 'completed' GROUP BY tenant_id, DATE(created_at);

CREATE OR REPLACE VIEW product_performance AS
SELECT s.tenant_id, si.product_name as name, SUM(si.quantity) as quantity, SUM(si.total_price) as revenue
FROM public.sale_items si JOIN public.sales s ON si.sale_id = s.id
WHERE s.status = 'completed' GROUP BY s.tenant_id, si.product_name;

-- 11. INITIAL SEED
-- ============================================================================
INSERT INTO public.tenants (id, name, slug, type, contact_email)
VALUES 
('00000000-0000-0000-0000-000000000001', 'Platform Admin', 'platform-admin', 'super', 'admin@platform.com'),
('00000000-0000-0000-0000-000000000002', 'Default Store', 'default-store', 'vendor', 'store@example.com')
ON CONFLICT DO NOTHING;
