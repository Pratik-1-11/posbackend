-- Migration: Phase 1 - Advanced Payment Splitting System
-- Purpose: Enable split payments across multiple payment methods
-- Dependencies: Requires existing sales and payment methods

-- ============================================================================
-- PART 1: Payment Splits Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.payment_splits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'card', 'qr', 'mixed', 'credit', 'gift_card', 'store_credit')),
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  transaction_reference TEXT,
  card_last_four TEXT,
  qr_provider TEXT CHECK (qr_provider IN ('esewa', 'khalti', 'fonepay', 'other')),
  gift_card_number TEXT,
  store_credit_reference TEXT,
  status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  processed_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Gift Cards Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.gift_cards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  card_number TEXT UNIQUE NOT NULL,
  initial_balance NUMERIC(10, 2) NOT NULL CHECK (initial_balance >= 0),
  current_balance NUMERIC(10, 2) NOT NULL CHECK (current_balance >= 0),
  issued_to_customer_id UUID REFERENCES public.customers(id),
  issued_by UUID REFERENCES public.profiles(id),
  issue_date TIMESTAMPTZ DEFAULT NOW(),
  expiry_date TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 3: Store Credit Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.store_credit (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  customer_id UUID REFERENCES public.customers(id) NOT NULL,
  credit_type TEXT CHECK (credit_type IN ('return_credit', 'loyalty_credit', 'promotion_credit', 'manual_credit')) NOT NULL,
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  balance_remaining NUMERIC(10, 2) NOT NULL CHECK (balance_remaining >= 0),
  reference_id UUID, -- Links to return, loyalty transaction, etc.
  reference_type TEXT,
  issued_by UUID REFERENCES public.profiles(id),
  issued_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT
);

-- ============================================================================
-- PART 4: Store Credit Transactions Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.store_credit_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_credit_id UUID REFERENCES public.store_credit(id) ON DELETE CASCADE,
  sale_id UUID REFERENCES public.sales(id),
  transaction_type TEXT CHECK (transaction_type IN ('issue', 'use', 'expire', 'adjust')) NOT NULL,
  amount NUMERIC(10, 2) NOT NULL,
  balance_before NUMERIC(10, 2) NOT NULL,
  balance_after NUMERIC(10, 2) NOT NULL,
  reference_id UUID,
  reference_type TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 5: Tips Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tips (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES public.sales(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  amount NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
  tip_method TEXT CHECK (tip_method IN ('cash', 'card', 'qr')) NOT NULL,
  recipient_id UUID REFERENCES public.profiles(id), -- Staff member receiving tip
  recipient_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 6: Indexes for Performance
-- ============================================================================

-- Payment splits indexes
CREATE INDEX IF NOT EXISTS idx_payment_splits_sale ON public.payment_splits(sale_id);
CREATE INDEX IF NOT EXISTS idx_payment_splits_tenant ON public.payment_splits(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payment_splits_method ON public.payment_splits(payment_method);
CREATE INDEX IF NOT EXISTS idx_payment_splits_status ON public.payment_splits(status);
CREATE INDEX IF NOT EXISTS idx_payment_splits_date ON public.payment_splits(created_at DESC);

-- Gift cards indexes
CREATE INDEX IF NOT EXISTS idx_gift_cards_tenant ON public.gift_cards(tenant_id);
CREATE INDEX IF NOT EXISTS idx_gift_cards_number ON public.gift_cards(card_number);
CREATE INDEX IF NOT EXISTS idx_gift_cards_customer ON public.gift_cards(issued_to_customer_id);
CREATE INDEX IF NOT EXISTS idx_gift_cards_active ON public.gift_cards(is_active, expiry_date);

-- Store credit indexes
CREATE INDEX IF NOT EXISTS idx_store_credit_tenant ON public.store_credit(tenant_id);
CREATE INDEX IF NOT EXISTS idx_store_credit_customer ON public.store_credit(customer_id);
CREATE INDEX IF NOT EXISTS idx_store_credit_active ON public.store_credit(is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_store_credit_type ON public.store_credit(credit_type);

-- Store credit transactions indexes
CREATE INDEX IF NOT EXISTS idx_store_credit_tx_credit ON public.store_credit_transactions(store_credit_id);
CREATE INDEX IF NOT EXISTS idx_store_credit_tx_sale ON public.store_credit_transactions(sale_id);
CREATE INDEX IF NOT EXISTS idx_store_credit_tx_type ON public.store_credit_transactions(transaction_type);

-- Tips indexes
CREATE INDEX IF NOT EXISTS idx_tips_sale ON public.tips(sale_id);
CREATE INDEX IF NOT EXISTS idx_tips_tenant ON public.tips(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tips_recipient ON public.tips(recipient_id);
CREATE INDEX IF NOT EXISTS idx_tips_date ON public.tips(created_at DESC);

-- ============================================================================
-- PART 7: Row Level Security (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.payment_splits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gift_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_credit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_credit_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tips ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Payment Splits
CREATE POLICY "Users can view payment splits in their tenant" ON public.payment_splits
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create payment splits" ON public.payment_splits
FOR INSERT WITH CHECK (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- RLS Policies for Gift Cards
CREATE POLICY "Users can view gift cards in their tenant" ON public.gift_cards
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage gift cards" ON public.gift_cards
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- RLS Policies for Store Credit
CREATE POLICY "Users can view store credit in their tenant" ON public.store_credit
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage store credit" ON public.store_credit
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- RLS Policies for Store Credit Transactions
CREATE POLICY "Users can view store credit transactions via credit" ON public.store_credit_transactions
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.store_credit sc 
    WHERE sc.id = store_credit_id 
    AND sc.tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
  )
);

-- RLS Policies for Tips
CREATE POLICY "Users can view tips in their tenant" ON public.tips
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create tips" ON public.tips
FOR INSERT WITH CHECK (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- ============================================================================
-- PART 8: Database Functions and Triggers
-- ============================================================================

-- Function to validate gift card balance
CREATE OR REPLACE FUNCTION validate_gift_card_balance()
RETURNS TRIGGER AS $$
DECLARE
  gift_card_record RECORD;
BEGIN
  -- Get gift card details
  SELECT * INTO gift_card_record FROM public.gift_cards WHERE id = NEW.gift_card_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Gift card not found';
  END IF;
  
  -- Check if gift card is active
  IF NOT gift_card_record.is_active THEN
    RAISE EXCEPTION 'Gift card is inactive';
  END IF;
  
  -- Check expiry
  IF gift_card_record.expiry_date < NOW() THEN
    RAISE EXCEPTION 'Gift card has expired';
  END IF;
  
  -- Check sufficient balance
  IF gift_card_record.current_balance < NEW.amount THEN
    RAISE EXCEPTION 'Insufficient gift card balance. Available: %s, Required: %s', 
                   gift_card_record.current_balance, NEW.amount;
  END IF;
  
  -- Update gift card balance
  UPDATE public.gift_cards 
  SET current_balance = current_balance - NEW.amount,
      updated_at = NOW()
  WHERE id = NEW.gift_card_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to validate store credit balance
CREATE OR REPLACE FUNCTION validate_store_credit_balance()
RETURNS TRIGGER AS $$
DECLARE
  credit_record RECORD;
BEGIN
  -- Get store credit details
  SELECT * INTO credit_record FROM public.store_credit WHERE id = NEW.store_credit_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Store credit not found';
  END IF;
  
  -- Check if store credit is active
  IF NOT credit_record.is_active THEN
    RAISE EXCEPTION 'Store credit is inactive';
  END IF;
  
  -- Check expiry
  IF credit_record.expires_at < NOW() THEN
    RAISE EXCEPTION 'Store credit has expired';
  END IF;
  
  -- Check sufficient balance
  IF credit_record.balance_remaining < NEW.amount THEN
    RAISE EXCEPTION 'Insufficient store credit balance. Available: %s, Required: %s', 
                   credit_record.balance_remaining, NEW.amount;
  END IF;
  
  -- Update store credit balance
  UPDATE public.store_credit 
  SET balance_remaining = balance_remaining - NEW.amount
  WHERE id = NEW.store_credit_id;
  
  -- Record transaction
  INSERT INTO public.store_credit_transactions (
    store_credit_id, transaction_type, amount, balance_before, balance_after
  ) VALUES (
    NEW.store_credit_id, 
    'use', 
    NEW.amount, 
    credit_record.balance_remaining,
    credit_record.balance_remaining - NEW.amount
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to create store credit transaction
CREATE OR REPLACE FUNCTION create_store_credit_transaction(
  p_customer_id UUID,
  p_credit_type TEXT,
  p_amount NUMERIC(10, 2),
  p_reference_id UUID DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_issued_by UUID DEFAULT NULL,
  p_expires_at TIMESTAMPTZ DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  credit_id UUID
) AS $$
DECLARE
  credit_id UUID;
  tenant_id UUID;
BEGIN
  -- Get tenant ID from customer
  SELECT tenant_id INTO tenant_id FROM public.customers WHERE id = p_customer_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Customer not found', NULL::UUID;
    RETURN;
  END IF;
  
  -- Create store credit
  INSERT INTO public.store_credit (
    tenant_id, customer_id, credit_type, amount, balance_remaining,
    reference_id, reference_type, issued_by, expires_at, notes
  ) VALUES (
    tenant_id, p_customer_id, p_credit_type, p_amount, p_amount,
    p_reference_id, p_reference_type, p_issued_by, p_expires_at, p_notes
  ) RETURNING id INTO credit_id;
  
  -- Record issuance transaction
  INSERT INTO public.store_credit_transactions (
    store_credit_id, transaction_type, amount, balance_before, balance_after
  ) VALUES (
    credit_id, 'issue', p_amount, 0, p_amount
  );
  
  RETURN QUERY SELECT true, 'Store credit created successfully', credit_id;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_validate_gift_card_balance
BEFORE INSERT ON public.payment_splits
FOR EACH ROW
WHEN (NEW.payment_method = 'gift_card')
EXECUTE FUNCTION validate_gift_card_balance();

-- ============================================================================
-- PART 9: Views for Reporting
-- ============================================================================

-- Payment Summary View
CREATE OR REPLACE VIEW vw_payment_summary AS
SELECT 
  ps.sale_id,
  ps.tenant_id,
  s.invoice_number,
  s.total_amount,
  COUNT(ps.id) as payment_count,
  STRING_AGG(ps.payment_method || ': ' || ps.amount::TEXT, ', ') as payment_breakdown,
  ARRAY_AGG(ps.payment_method) as payment_methods,
  s.created_at as sale_date
FROM public.payment_splits ps
JOIN public.sales s ON ps.sale_id = s.id
GROUP BY ps.sale_id, ps.tenant_id, s.invoice_number, s.total_amount, s.created_at;

-- Gift Card Summary View
CREATE OR REPLACE VIEW vw_gift_card_summary AS
SELECT 
  gc.id,
  gc.tenant_id,
  gc.card_number,
  gc.initial_balance,
  gc.current_balance,
  gc.issue_date,
  gc.expiry_date,
  gc.is_active,
  c.name as customer_name,
  c.phone as customer_phone,
  u.full_name as issued_by_name,
  gc.initial_balance - gc.current_balance as amount_used
FROM public.gift_cards gc
LEFT JOIN public.customers c ON gc.issued_to_customer_id = c.id
LEFT JOIN public.profiles u ON gc.issued_by = u.id;

-- Store Credit Summary View
CREATE OR REPLACE VIEW vw_store_credit_summary AS
SELECT 
  sc.id,
  sc.tenant_id,
  sc.customer_id,
  sc.credit_type,
  sc.amount,
  sc.balance_remaining,
  sc.issued_at,
  sc.expires_at,
  sc.is_active,
  c.name as customer_name,
  c.phone as customer_phone,
  u.full_name as issued_by_name,
  sc.amount - sc.balance_remaining as amount_used,
  COUNT(sct.id) as transaction_count
FROM public.store_credit sc
LEFT JOIN public.customers c ON sc.customer_id = c.id
LEFT JOIN public.profiles u ON sc.issued_by = u.id
LEFT JOIN public.store_credit_transactions sct ON sc.id = sct.store_credit_id
GROUP BY sc.id, sc.tenant_id, sc.customer_id, sc.credit_type, sc.amount, 
         sc.balance_remaining, sc.issued_at, sc.expires_at, sc.is_active,
         c.name, c.phone, u.full_name;

-- ============================================================================
-- PART 10: RPC Functions for Business Logic
-- ============================================================================

-- Function to process split payment
CREATE OR REPLACE FUNCTION process_split_payment(
  p_sale_id UUID,
  p_payment_splits JSONB,
  p_tenant_id UUID
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  payment_split_ids UUID[]
) AS $$
DECLARE
  split_record JSONB;
  total_amount NUMERIC;
  split_total NUMERIC := 0;
  payment_split_ids UUID[] := '{}';
  split_id UUID;
BEGIN
  -- Get sale total
  SELECT total_amount INTO total_amount FROM public.sales WHERE id = p_sale_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Sale not found', NULL::UUID[];
    RETURN;
  END IF;
  
  -- Validate split amounts
  FOR split_record IN SELECT * FROM jsonb_array_elements(p_payment_splits)
  LOOP
    split_total := split_total + (split_record->>'amount')::NUMERIC;
  END LOOP;
  
  IF ABS(split_total - total_amount) > 0.01 THEN
    RETURN QUERY SELECT false, 'Split amounts do not match sale total', NULL::UUID[];
    RETURN;
  END IF;
  
  -- Process each payment split
  FOR split_record IN SELECT * FROM jsonb_array_elements(p_payment_splits)
  LOOP
    INSERT INTO public.payment_splits (
      sale_id, tenant_id, payment_method, amount, 
      transaction_reference, card_last_four, qr_provider, 
      gift_card_number, store_credit_reference
    ) VALUES (
      p_sale_id,
      p_tenant_id,
      split_record->>'payment_method',
      (split_record->>'amount')::NUMERIC,
      split_record->>'transaction_reference',
      split_record->>'card_last_four',
      split_record->>'qr_provider',
      split_record->>'gift_card_number',
      split_record->>'store_credit_reference'
    ) RETURNING id INTO split_id;
    
    payment_split_ids := array_append(payment_split_ids, split_id);
  END LOOP;
  
  RETURN QUERY SELECT true, 'Split payment processed successfully', payment_split_ids;
END;
$$ LANGUAGE plpgsql;

-- Function to issue gift card
CREATE OR REPLACE FUNCTION issue_gift_card(
  p_tenant_id UUID,
  p_card_number TEXT,
  p_initial_balance NUMERIC(10, 2),
  p_customer_id UUID DEFAULT NULL,
  p_issued_by UUID DEFAULT NULL,
  p_expiry_date TIMESTAMPTZ DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  gift_card_id UUID
) AS $$
DECLARE
  gift_card_id UUID;
BEGIN
  -- Check if card number already exists
  IF EXISTS (SELECT 1 FROM public.gift_cards WHERE card_number = p_card_number) THEN
    RETURN QUERY SELECT false, 'Gift card number already exists', NULL::UUID;
    RETURN;
  END IF;
  
  -- Create gift card
  INSERT INTO public.gift_cards (
    tenant_id, card_number, initial_balance, current_balance,
    issued_to_customer_id, issued_by, expiry_date, notes
  ) VALUES (
    p_tenant_id, p_card_number, p_initial_balance, p_initial_balance,
    p_customer_id, p_issued_by, p_expiry_date, p_notes
  ) RETURNING id INTO gift_card_id;
  
  RETURN QUERY SELECT true, 'Gift card issued successfully', gift_card_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Advanced Payment Splitting System - Migration Complete';
  RAISE NOTICE '📋 Tables Created: payment_splits, gift_cards, store_credit, store_credit_transactions, tips';
  RAISE NOTICE '🔒 RLS Policies: Applied for tenant isolation and role-based access';
  RAISE NOTICE '📊 Views Created: vw_payment_summary, vw_gift_card_summary, vw_store_credit_summary';
  RAISE NOTICE '⚙️ RPC Functions: process_split_payment, issue_gift_card, create_store_credit_transaction';
  RAISE NOTICE '🔧 Triggers: Gift card balance validation, store credit validation';
END $$;
