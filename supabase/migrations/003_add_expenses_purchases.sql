-- Migration: Add Expenses and Purchases Tables
-- Created: 2025-12-31

-- 1. EXPENSES TABLE
CREATE TABLE IF NOT EXISTS public.expenses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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

-- 2. PURCHASES TABLE
CREATE TABLE IF NOT EXISTS public.purchases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
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

-- INDEXES for better query performance
CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses(date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON public.expenses(category);
CREATE INDEX IF NOT EXISTS idx_expenses_status ON public.expenses(status);

CREATE INDEX IF NOT EXISTS idx_purchases_date ON public.purchases(purchase_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON public.purchases(supplier_name);
CREATE INDEX IF NOT EXISTS idx_purchases_status ON public.purchases(status);

-- ENABLE RLS
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;

-- RLS POLICIES for Expenses
DROP POLICY IF EXISTS "Enable all access for authenticated users" ON public.expenses;
DROP POLICY IF EXISTS "View expenses" ON public.expenses;
DROP POLICY IF EXISTS "Manage expenses" ON public.expenses;

CREATE POLICY "View expenses" ON public.expenses 
FOR SELECT TO authenticated USING (true);

CREATE POLICY "Manage expenses" ON public.expenses 
FOR ALL TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('super_admin', 'branch_admin')
  )
);

-- RLS POLICIES for Purchases
DROP POLICY IF EXISTS "View purchases" ON public.purchases;
DROP POLICY IF EXISTS "Manage purchases" ON public.purchases;

CREATE POLICY "View purchases" ON public.purchases 
FOR SELECT TO authenticated USING (true);

CREATE POLICY "Manage purchases" ON public.purchases 
FOR ALL TO authenticated 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role IN ('super_admin', 'branch_admin', 'inventory_manager')
  )
);

-- TRIGGERS for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_expenses_updated_at ON public.expenses;
CREATE TRIGGER update_expenses_updated_at
  BEFORE UPDATE ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_purchases_updated_at ON public.purchases;
CREATE TRIGGER update_purchases_updated_at
  BEFORE UPDATE ON public.purchases
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- VIEWS for Analytics
CREATE OR REPLACE VIEW expense_summary AS
SELECT 
  DATE(date) as expense_date,
  category,
  status,
  COUNT(id) as total_entries,
  SUM(amount) as total_amount
FROM public.expenses
GROUP BY DATE(date), category, status
ORDER BY expense_date DESC;

CREATE OR REPLACE VIEW purchase_summary AS
SELECT 
  DATE(purchase_date) as purchase_date,
  supplier_name,
  status,
  COUNT(id) as total_entries,
  SUM(quantity) as total_quantity,
  SUM(total_amount) as total_spent
FROM public.purchases
GROUP BY DATE(purchase_date), supplier_name, status
ORDER BY purchase_date DESC;
