-- ==========================================
-- POS SYSTEM MASTER DATABASE SETUP
-- Consolidated Migration for Manual Execution
-- Created: 2026-01-01
-- ==========================================

-- 1. EXTENSIONS & UTILITIES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DROP FUNCTION IF EXISTS update_updated_at_column CASCADE;
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. BRANCHES
CREATE TABLE IF NOT EXISTS public.branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  location TEXT,
  contact_number TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. PROFILES (Extends Auth Users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT,
  full_name TEXT,
  email TEXT,
  role TEXT CHECK (role IN ('super_admin', 'branch_admin', 'cashier', 'inventory_manager', 'waiter', 'manager', 'admin')),
  branch_id UUID REFERENCES public.branches(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CATEGORIES
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SUPPLIERS
CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. PRODUCTS
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
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. CUSTOMERS
CREATE TABLE IF NOT EXISTS public.customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  email TEXT,
  address TEXT,
  total_credit NUMERIC(10, 2) DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. SALES
CREATE TABLE IF NOT EXISTS public.sales (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  invoice_number TEXT UNIQUE NOT NULL,
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
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. SALE ITEMS
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

-- 10. STOCK MOVEMENTS
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

-- 11. CUSTOMER TRANSACTIONS (Ledger)
CREATE TABLE IF NOT EXISTS public.customer_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  type TEXT CHECK (type IN ('opening_balance', 'sale', 'payment', 'refund', 'adjustment', 'return')),
  amount NUMERIC(10, 2) NOT NULL,
  description TEXT,
  reference_id UUID,
  performed_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. CUSTOMER HISTORY
CREATE TABLE IF NOT EXISTS public.customer_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  field_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  changed_by UUID REFERENCES auth.users(id),
  changed_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. EXPENSES
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

-- 14. PURCHASES
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

-- 15. SETTINGS
CREATE TABLE IF NOT EXISTS public.settings (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) DEFAULT 'My Local Mart',
  address TEXT DEFAULT 'Kathmandu, Nepal',
  phone VARCHAR(20) DEFAULT '9800000000',
  email VARCHAR(255) DEFAULT 'store@example.com',
  pan VARCHAR(50) DEFAULT '000000000',
  footer_message TEXT DEFAULT 'Thank you for shopping with us!',
  tax_rate DECIMAL(5, 2) DEFAULT 13.00,
  currency VARCHAR(10) DEFAULT 'NPR',
  receipt_settings JSONB DEFAULT '{"header": "Thank you for your purchase!", "footer": "Please come again!", "showTax": true, "showLogo": true}',
  notification_settings JSONB DEFAULT '{"email": true, "sms": true, "lowStock": true}',
  security_settings JSONB DEFAULT '{"twoFactorAuth": false, "sessionTimeout": 30, "requirePasswordForDelete": true}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 16. FUNCTIONS & RPCs

-- Atomic Stock Decrement
DROP FUNCTION IF EXISTS decrement_stock(UUID, INTEGER);
CREATE OR REPLACE FUNCTION decrement_stock(product_id UUID, quantity INTEGER)
RETURNS VOID AS $$
BEGIN
  UPDATE public.products 
  SET stock_quantity = stock_quantity - quantity
  WHERE id = product_id;
END;
$$ LANGUAGE plpgsql;

-- Add Customer Transaction and Update Balance
DROP FUNCTION IF EXISTS add_customer_transaction(UUID, TEXT, NUMERIC, TEXT, UUID, UUID);
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
BEGIN
  INSERT INTO public.customer_transactions (customer_id, type, amount, description, reference_id, performed_by)
  VALUES (p_customer_id, p_type, p_amount, p_description, p_reference_id, p_user_id)
  RETURNING id INTO v_transaction_id;

  IF p_type IN ('sale', 'opening_balance') THEN
    UPDATE public.customers SET total_credit = total_credit + p_amount WHERE id = p_customer_id;
  ELSIF p_type IN ('payment', 'return') THEN
    UPDATE public.customers SET total_credit = total_credit - p_amount WHERE id = p_customer_id;
  ELSIF p_type = 'adjustment' THEN
    UPDATE public.customers SET total_credit = total_credit + p_amount WHERE id = p_customer_id;
  END IF;

  RETURN v_transaction_id;
END;
$$ LANGUAGE plpgsql;

-- Process POS Sale (Atomic)
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
BEGIN
  v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(floor(random() * 10000)::text, 4, '0');
  v_sub_total := p_total_amount + p_discount_amount;

  INSERT INTO public.sales (
    invoice_number, cashier_id, branch_id, customer_id, customer_name,
    payment_method, payment_details, sub_total, discount_amount,
    taxable_amount, vat_amount, total_amount, status, created_at
  )
  VALUES (
    v_invoice_number, p_cashier_id, p_branch_id, p_customer_id, p_customer_name,
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
    WHERE id = (v_item->>'product_id')::UUID;
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

  -- Handle excess cash payment towards existing debt
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
$$ LANGUAGE plpgsql;

-- Customer History Tracker Function
DROP FUNCTION IF EXISTS log_customer_changes() CASCADE;
CREATE OR REPLACE FUNCTION log_customer_changes()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'UPDATE') THEN
    IF (OLD.name IS DISTINCT FROM NEW.name) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value) VALUES (OLD.id, 'name', OLD.name, NEW.name);
    END IF;
    IF (OLD.phone IS DISTINCT FROM NEW.phone) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value) VALUES (OLD.id, 'phone', OLD.phone, NEW.phone);
    END IF;
    IF (OLD.email IS DISTINCT FROM NEW.email) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value) VALUES (OLD.id, 'email', OLD.email, NEW.email);
    END IF;
    IF (OLD.address IS DISTINCT FROM NEW.address) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value) VALUES (OLD.id, 'address', OLD.address, NEW.address);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 17. TRIGGERS
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_customers_updated_at ON public.customers;
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_expenses_updated_at ON public.expenses;
CREATE TRIGGER update_expenses_updated_at BEFORE UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_purchases_updated_at ON public.purchases;
CREATE TRIGGER update_purchases_updated_at BEFORE UPDATE ON public.purchases FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_settings_updated_at ON public.settings;
CREATE TRIGGER update_settings_updated_at BEFORE UPDATE ON public.settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS customer_history_trigger ON public.customers;
CREATE TRIGGER customer_history_trigger AFTER UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION log_customer_changes();

-- 18. VIEWS

CREATE OR REPLACE VIEW daily_sales_summary AS
SELECT DATE(created_at) as sale_date, COUNT(id) as total_transactions, SUM(sub_total) as total_sub_total, SUM(discount_amount) as total_discount, SUM(taxable_amount) as total_taxable, SUM(vat_amount) as total_vat, SUM(total_amount) as total_revenue
FROM public.sales GROUP BY DATE(created_at) ORDER BY sale_date DESC;

CREATE OR REPLACE VIEW cashier_performance AS
SELECT p.full_name as cashier_name, s.cashier_id, COUNT(s.id) as total_sales_count, SUM(s.total_amount) as total_revenue_generated
FROM public.sales s JOIN public.profiles p ON s.cashier_id = p.id GROUP BY s.cashier_id, p.full_name;

CREATE OR REPLACE VIEW expense_summary AS
SELECT DATE(date) as expense_date, category, status, COUNT(id) as total_entries, SUM(amount) as total_amount
FROM public.expenses GROUP BY DATE(date), category, status ORDER BY expense_date DESC;

CREATE OR REPLACE VIEW purchase_summary AS
SELECT DATE(purchase_date) as purchase_date, supplier_name, status, COUNT(id) as total_entries, SUM(quantity) as total_quantity, SUM(total_amount) as total_spent
FROM public.purchases GROUP BY DATE(purchase_date), supplier_name, status ORDER BY purchase_date DESC;

CREATE OR REPLACE VIEW product_performance AS
SELECT product_name as name, SUM(quantity) as quantity, SUM(total_price) as revenue
FROM public.sale_items GROUP BY product_name ORDER BY revenue DESC;

-- 19. RLS POLICIES (Comprehensive RBAC)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

-- Helper Function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin() 
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'super_admin')
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Helper Function to check if user is manager or admin
CREATE OR REPLACE FUNCTION public.is_manager_or_admin() 
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'super_admin', 'manager', 'branch_admin')
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- PROFILES Policies
DROP POLICY IF EXISTS "Admins manage all profiles" ON public.profiles;
CREATE POLICY "Admins manage all profiles" ON public.profiles FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "Users view all profiles" ON public.profiles;
CREATE POLICY "Users view all profiles" ON public.profiles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- PRODUCTS Policies
DROP POLICY IF EXISTS "Everyone views products" ON public.products;
CREATE POLICY "Everyone views products" ON public.products FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins/Managers manage products" ON public.products;
CREATE POLICY "Admins/Managers manage products" ON public.products FOR ALL USING (public.is_manager_or_admin());

-- SALES Policies
DROP POLICY IF EXISTS "Everyone views sales" ON public.sales;
CREATE POLICY "Everyone views sales" ON public.sales FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Cashiers and above create sales" ON public.sales;
CREATE POLICY "Cashiers and above create sales" ON public.sales FOR INSERT TO authenticated WITH CHECK (EXISTS (
  SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('cashier', 'admin', 'super_admin', 'manager', 'branch_admin')
));

-- CUSTOMERS Policies
DROP POLICY IF EXISTS "Everyone manages customers" ON public.customers;
CREATE POLICY "Everyone manages customers" ON public.customers FOR ALL TO authenticated USING (true);

-- EXPENSES & PURCHASES Policies
DROP POLICY IF EXISTS "Everyone views expenses" ON public.expenses;
CREATE POLICY "Everyone views expenses" ON public.expenses FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins/Managers manage expenses" ON public.expenses;
CREATE POLICY "Admins/Managers manage expenses" ON public.expenses FOR ALL USING (public.is_manager_or_admin());

DROP POLICY IF EXISTS "Everyone views purchases" ON public.purchases;
CREATE POLICY "Everyone views purchases" ON public.purchases FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins/Managers manage purchases" ON public.purchases;
CREATE POLICY "Admins/Managers manage purchases" ON public.purchases FOR ALL USING (public.is_manager_or_admin());

-- SETTINGS Policies
DROP POLICY IF EXISTS "Everyone views settings" ON public.settings;
CREATE POLICY "Everyone views settings" ON public.settings FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins manage settings" ON public.settings;
CREATE POLICY "Admins manage settings" ON public.settings FOR ALL USING (public.is_admin());

-- 20. SEED DATA
INSERT INTO settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
