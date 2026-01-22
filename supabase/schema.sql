-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. PROFILES (Extends Auth Users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT,
  full_name TEXT,
  role TEXT CHECK (role IN ('super_admin', 'branch_admin', 'cashier', 'inventory_manager')),
  branch_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. BRANCHES
CREATE TABLE IF NOT EXISTS public.branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  location TEXT,
  contact_number TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add Foreign Key to profiles for branch_id (safe check)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_profiles_branch'
  ) THEN
    ALTER TABLE public.profiles 
    ADD CONSTRAINT fk_profiles_branch 
    FOREIGN KEY (branch_id) REFERENCES public.branches(id);
  END IF;
END $$;

-- 3. CATEGORIES
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. SUPPLIERS
CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. PRODUCTS
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  barcode TEXT UNIQUE,
  description TEXT,
  category_id UUID REFERENCES public.categories(id),
  supplier_id UUID REFERENCES public.suppliers(id),
  cost_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
  selling_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
  stock_quantity INTEGER NOT NULL DEFAULT 0,
  min_stock_level INTEGER DEFAULT 5,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. SALES
CREATE TABLE IF NOT EXISTS public.sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  invoice_number TEXT UNIQUE NOT NULL,
  cashier_id UUID REFERENCES public.profiles(id),
  branch_id UUID REFERENCES public.branches(id),
  customer_name TEXT DEFAULT 'Walk-in',
  payment_method TEXT CHECK (payment_method IN ('cash', 'card', 'qr', 'mixed')),
  sub_total NUMERIC(10, 2) NOT NULL,
  discount_amount NUMERIC(10, 2) DEFAULT 0,
  taxable_amount NUMERIC(10, 2) NOT NULL,
  vat_amount NUMERIC(10, 2) NOT NULL,
  total_amount NUMERIC(10, 2) NOT NULL,
  status TEXT DEFAULT 'completed' CHECK (status IN ('completed', 'cancelled', 'refunded')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. SALE ITEMS
CREATE TABLE IF NOT EXISTS public.sale_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.products(id),
  product_name TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price NUMERIC(10, 2) NOT NULL,
  total_price NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. STOCK MOVEMENTS
CREATE TABLE IF NOT EXISTS public.stock_movements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES public.products(id),
  branch_id UUID REFERENCES public.branches(id),
  type TEXT CHECK (type IN ('in', 'out', 'sale', 'adjustment', 'return')),
  quantity INTEGER NOT NULL,
  reason TEXT,
  performed_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. AUDIT LOGS
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  table_name TEXT NOT NULL,
  record_id UUID,
  action TEXT NOT NULL,
  old_data JSONB,
  new_data JSONB,
  performed_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS POLICIES ---------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

-- Drop existing policies first to avoid conflicts
DROP POLICY IF EXISTS "View own profile" ON public.profiles;
DROP POLICY IF EXISTS "View products" ON public.products;
DROP POLICY IF EXISTS "Manage products" ON public.products;
DROP POLICY IF EXISTS "Create sales" ON public.sales;
DROP POLICY IF EXISTS "View sales" ON public.sales;

-- Profiles: Users can view their own profile
CREATE POLICY "View own profile" ON public.profiles 
FOR SELECT USING (auth.uid() = id);

-- Products: All authenticated users can view products
CREATE POLICY "View products" ON public.products 
FOR SELECT TO authenticated USING (true);

-- Products: Only Inventory Managers and Admins can create/update
CREATE POLICY "Manage products" ON public.products 
FOR ALL TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('super_admin', 'branch_admin', 'inventory_manager')
  )
);

-- Sales: Cashiers can create sales
CREATE POLICY "Create sales" ON public.sales 
FOR INSERT TO authenticated 
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('cashier', 'branch_admin', 'super_admin')
  )
);

-- Sales: View sales - Admin sees all, Cashier sees own
CREATE POLICY "View sales" ON public.sales 
FOR SELECT TO authenticated 
USING (
  (auth.uid() = cashier_id) OR
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('super_admin', 'branch_admin')
  )
);

-- RPC FUNCTION: atomic stock decrement
CREATE OR REPLACE FUNCTION decrement_stock(product_id UUID, quantity INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.products
  SET stock_quantity = stock_quantity - quantity
  WHERE id = product_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found';
  END IF;
END;
$$ LANGUAGE plpgsql;

-- VIEW: Daily Sales Summary
CREATE OR REPLACE VIEW daily_sales_summary AS
SELECT 
  DATE(created_at) as sale_date,
  COUNT(id) as total_transactions,
  SUM(sub_total) as total_sub_total,
  SUM(discount_amount) as total_discount,
  SUM(taxable_amount) as total_taxable,
  SUM(vat_amount) as total_vat,
  SUM(total_amount) as total_revenue
FROM public.sales
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

-- VIEW: Cashier Performance
CREATE OR REPLACE VIEW cashier_performance AS
SELECT 
  p.full_name as cashier_name,
  s.cashier_id,
  COUNT(s.id) as total_sales_count,
  SUM(s.total_amount) as total_revenue_generated
FROM public.sales s
JOIN public.profiles p ON s.cashier_id = p.id
GROUP BY s.cashier_id, p.full_name;
