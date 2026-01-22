-- Migration: Add Customers and Credit System
-- Created: 2025-12-31

-- 1. CUSTOMERS TABLE
CREATE TABLE IF NOT EXISTS public.customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  email TEXT,
  address TEXT,
  total_credit NUMERIC(10, 2) DEFAULT 0, -- Positive means debt (receivable)
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. CUSTOMER TRANSACTIONS TABLE (Ledger)
CREATE TABLE IF NOT EXISTS public.customer_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  type TEXT CHECK (type IN ('opening_balance', 'sale', 'payment', 'refund', 'adjustment')),
  amount NUMERIC(10, 2) NOT NULL, -- Amount of the transaction
  description TEXT,
  reference_id UUID, -- Can link to sale_id
  performed_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. LINK SALES TO CUSTOMERS
ALTER TABLE public.sales 
ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES public.customers(id);

-- Update payment_method check constraint to include 'credit'
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_payment_method_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_payment_method_check 
  CHECK (payment_method IN ('cash', 'card', 'qr', 'mixed', 'credit'));

-- 4. RLS POLICIES
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_transactions ENABLE ROW LEVEL SECURITY;

-- Customers
DROP POLICY IF EXISTS "View customers" ON public.customers;
DROP POLICY IF EXISTS "Manage customers" ON public.customers;

CREATE POLICY "View customers" ON public.customers 
FOR SELECT TO authenticated USING (true);

CREATE POLICY "Manage customers" ON public.customers 
FOR ALL TO authenticated 
USING (true)
WITH CHECK (true);

-- Customer Transactions
DROP POLICY IF EXISTS "View transactions" ON public.customer_transactions;
DROP POLICY IF EXISTS "Manage transactions" ON public.customer_transactions;

CREATE POLICY "View transactions" ON public.customer_transactions 
FOR SELECT TO authenticated USING (true);

CREATE POLICY "Manage transactions" ON public.customer_transactions 
FOR ALL TO authenticated 
USING (true)
WITH CHECK (true);


-- 6. RPC FUNCTION to add transaction and update balance atomically
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
  -- Insert Transaction
  INSERT INTO public.customer_transactions (customer_id, type, amount, description, reference_id, performed_by)
  VALUES (p_customer_id, p_type, p_amount, p_description, p_reference_id, p_user_id)
  RETURNING id INTO v_transaction_id;

  -- Update Balance
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
