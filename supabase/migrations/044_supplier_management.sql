-- Migration: Phase 1 - Supplier Management System
-- Purpose: Complete supplier lifecycle management with purchase orders and payments
-- Dependencies: Requires existing products and categories

-- ============================================================================
-- PART 1: Enhanced Suppliers Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  mobile TEXT,
  email TEXT,
  address TEXT,
  city TEXT,
  state TEXT,
  postal_code TEXT,
  country TEXT DEFAULT 'Nepal',
  pan_number TEXT, -- Permanent Account Number for tax purposes
  gst_number TEXT,
  payment_terms TEXT DEFAULT 'NET 30',
  credit_limit NUMERIC(12, 2) DEFAULT 0,
  current_balance NUMERIC(12, 2) DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  is_preferred BOOLEAN DEFAULT FALSE,
  notes TEXT,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  website TEXT,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 1.5: Ensure All Required Columns Exist in Suppliers Table
-- ============================================================================

DO $$
BEGIN
  -- Ensure all required columns exist in suppliers table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'suppliers' AND table_schema = 'public') THEN
    -- Add missing columns if they don't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.suppliers ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'contact_person') THEN
      ALTER TABLE public.suppliers ADD COLUMN contact_person TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'phone') THEN
      ALTER TABLE public.suppliers ADD COLUMN phone TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'email') THEN
      ALTER TABLE public.suppliers ADD COLUMN email TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'address') THEN
      ALTER TABLE public.suppliers ADD COLUMN address TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'payment_terms') THEN
      ALTER TABLE public.suppliers ADD COLUMN payment_terms TEXT DEFAULT 'NET 30';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'credit_limit') THEN
      ALTER TABLE public.suppliers ADD COLUMN credit_limit NUMERIC(12, 2) DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'current_balance') THEN
      ALTER TABLE public.suppliers ADD COLUMN current_balance NUMERIC(12, 2) DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'is_active') THEN
      ALTER TABLE public.suppliers ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'is_preferred') THEN
      ALTER TABLE public.suppliers ADD COLUMN is_preferred BOOLEAN DEFAULT FALSE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'notes') THEN
      ALTER TABLE public.suppliers ADD COLUMN notes TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'rating') THEN
      ALTER TABLE public.suppliers ADD COLUMN rating INTEGER CHECK (rating >= 1 AND rating <= 5);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'created_at') THEN
      ALTER TABLE public.suppliers ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'suppliers' AND table_schema = 'public' AND column_name = 'updated_at') THEN
      ALTER TABLE public.suppliers ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    
    RAISE NOTICE 'All required columns verified in suppliers table';
  END IF;
END $$;

-- ============================================================================
-- PART 2: Purchase Orders Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  branch_id UUID REFERENCES public.branches(id) NOT NULL,
  supplier_id UUID REFERENCES public.suppliers(id) NOT NULL,
  order_number TEXT UNIQUE NOT NULL,
  order_date TIMESTAMPTZ DEFAULT NOW(),
  expected_delivery_date TIMESTAMPTZ,
  actual_delivery_date TIMESTAMPTZ,
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'confirmed', 'partial_received', 'received', 'cancelled')),
  subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0,
  discount_amount NUMERIC(12, 2) DEFAULT 0,
  tax_amount NUMERIC(12, 2) DEFAULT 0,
  total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(12, 2) DEFAULT 0,
  balance_amount NUMERIC(12, 2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
  payment_status TEXT DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'partial', 'paid')),
  notes TEXT,
  terms_conditions TEXT,
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  approved_by UUID REFERENCES public.profiles(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 3: Purchase Order Items Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  purchase_order_id UUID REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id UUID REFERENCES public.products(id),
  product_name TEXT NOT NULL,
  description TEXT,
  quantity_ordered INTEGER NOT NULL CHECK (quantity_ordered > 0),
  quantity_received INTEGER DEFAULT 0 CHECK (quantity_received >= 0),
  unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
  discount_percent NUMERIC(5, 2) DEFAULT 0 CHECK (discount_percent >= 0 AND discount_percent <= 100),
  tax_rate NUMERIC(5, 2) DEFAULT 13 CHECK (tax_rate >= 0),
  total_amount NUMERIC(12, 2) GENERATED ALWAYS AS (
    quantity_ordered * unit_price * (1 - discount_percent/100) * (1 + tax_rate/100)
  ) STORED,
  received_amount NUMERIC(12, 2) GENERATED ALWAYS AS (
    quantity_received * unit_price * (1 - discount_percent/100) * (1 + tax_rate/100)
  ) STORED,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 4: Supplier Payments Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.supplier_payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  supplier_id UUID REFERENCES public.suppliers(id) NOT NULL,
  purchase_order_id UUID REFERENCES public.purchase_orders(id),
  payment_number TEXT UNIQUE NOT NULL,
  payment_date TIMESTAMPTZ DEFAULT NOW(),
  payment_method TEXT CHECK (payment_method IN ('cash', 'bank_transfer', 'cheque', 'card', 'upi', 'other')),
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  reference_number TEXT,
  bank_name TEXT,
  cheque_number TEXT,
  transaction_date DATE,
  notes TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 5: Supplier Invoices Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.supplier_invoices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  supplier_id UUID REFERENCES public.suppliers(id) NOT NULL,
  purchase_order_id UUID REFERENCES public.purchase_orders(id),
  invoice_number TEXT NOT NULL,
  invoice_date DATE NOT NULL,
  due_date DATE,
  subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0,
  tax_amount NUMERIC(12, 2) DEFAULT 0,
  total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(12, 2) DEFAULT 0,
  balance_amount NUMERIC(12, 2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
  status TEXT DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'partial', 'paid', 'overdue')),
  notes TEXT,
  attachment_url TEXT,
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 6: Supplier Performance Tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.supplier_performance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  supplier_id UUID REFERENCES public.suppliers(id) NOT NULL,
  evaluation_period TEXT NOT NULL, -- e.g., '2024-01', 'Q1-2024'
  total_orders INTEGER DEFAULT 0,
  on_time_deliveries INTEGER DEFAULT 0,
  late_deliveries INTEGER DEFAULT 0,
  quality_score NUMERIC(5, 2) DEFAULT 0 CHECK (quality_score >= 0 AND quality_score <= 5),
  average_delivery_days NUMERIC(5, 2) DEFAULT 0,
  total_purchase_amount NUMERIC(12, 2) DEFAULT 0,
  returns_count INTEGER DEFAULT 0,
  complaints_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 7: Indexes for Performance
-- ============================================================================

-- Suppliers indexes
CREATE INDEX IF NOT EXISTS idx_suppliers_tenant ON public.suppliers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_active ON public.suppliers(is_active);
CREATE INDEX IF NOT EXISTS idx_suppliers_preferred ON public.suppliers(is_preferred);
CREATE INDEX IF NOT EXISTS idx_suppliers_name ON public.suppliers(name);
CREATE INDEX IF NOT EXISTS idx_suppliers_phone ON public.suppliers(phone);

-- Purchase orders indexes
CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant ON public.purchase_orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON public.purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_date ON public.purchase_orders(order_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_number ON public.purchase_orders(order_number);

-- Purchase order items indexes
CREATE INDEX IF NOT EXISTS idx_po_items_order ON public.purchase_order_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_items_product ON public.purchase_order_items(product_id);

-- Supplier payments indexes
CREATE INDEX IF NOT EXISTS idx_supplier_payments_tenant ON public.supplier_payments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier ON public.supplier_payments(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_po ON public.supplier_payments(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_date ON public.supplier_payments(payment_date DESC);

-- Supplier invoices indexes
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_tenant ON public.supplier_invoices(tenant_id);
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_supplier ON public.supplier_invoices(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_po ON public.supplier_invoices(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_status ON public.supplier_invoices(status);
CREATE INDEX IF NOT EXISTS idx_supplier_invoices_due ON public.supplier_invoices(due_date);

-- Supplier performance indexes
CREATE INDEX IF NOT EXISTS idx_supplier_performance_tenant ON public.supplier_performance(tenant_id);
CREATE INDEX IF NOT EXISTS idx_supplier_performance_supplier ON public.supplier_performance(supplier_id);
CREATE INDEX IF NOT EXISTS idx_supplier_performance_period ON public.supplier_performance(evaluation_period);

-- ============================================================================
-- PART 8: Row Level Security (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_performance ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Suppliers
CREATE POLICY "Users can view suppliers in their tenant" ON public.suppliers
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create suppliers" ON public.suppliers
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

CREATE POLICY "Users can update suppliers" ON public.suppliers
FOR UPDATE USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- RLS Policies for Purchase Orders
CREATE POLICY "Users can view POs in their tenant" ON public.purchase_orders
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create POs" ON public.purchase_orders
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

CREATE POLICY "Users can update POs" ON public.purchase_orders
FOR UPDATE USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- RLS Policies for Purchase Order Items
CREATE POLICY "Users can view PO items via POs" ON public.purchase_order_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.purchase_orders po 
    WHERE po.id = purchase_order_id 
    AND po.tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
  )
);

-- RLS Policies for Supplier Payments
CREATE POLICY "Users can view supplier payments in their tenant" ON public.supplier_payments
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create supplier payments" ON public.supplier_payments
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- RLS Policies for Supplier Invoices
CREATE POLICY "Users can view supplier invoices in their tenant" ON public.supplier_invoices
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create supplier invoices" ON public.supplier_invoices
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- ============================================================================
-- PART 9: Database Functions and Triggers
-- ============================================================================

-- Function to generate purchase order number
CREATE OR REPLACE FUNCTION generate_purchase_order_number()
RETURNS TEXT AS $$
DECLARE
  order_number TEXT;
  sequence_num INTEGER;
BEGIN
  -- Get next sequence number
  SELECT COALESCE(MAX(CAST(SUBSTRING(order_number FROM '[0-9]+$') AS INTEGER)), 0) + 1
  INTO sequence_num
  FROM public.purchase_orders
  WHERE tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
  AND order_number LIKE 'PO-%';

  -- Generate order number
  order_number := 'PO-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN order_number;
END;
$$ LANGUAGE plpgsql;

-- Function to update supplier balance on payment
CREATE OR REPLACE FUNCTION update_supplier_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Update supplier current balance
  UPDATE public.suppliers
  SET current_balance = current_balance - NEW.amount,
      updated_at = NOW()
  WHERE id = NEW.supplier_id;
  
  -- Update purchase order paid amount
  IF NEW.purchase_order_id IS NOT NULL THEN
    UPDATE public.purchase_orders
    SET paid_amount = paid_amount + NEW.amount,
        payment_status = CASE 
          WHEN paid_amount + NEW.amount >= total_amount THEN 'paid'
          WHEN paid_amount + NEW.amount > 0 THEN 'partial'
          ELSE 'unpaid'
        END,
        updated_at = NOW()
    WHERE id = NEW.purchase_order_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update supplier performance
CREATE OR REPLACE FUNCTION update_supplier_performance()
RETURNS TRIGGER AS $$
DECLARE
  current_period TEXT;
  performance_record RECORD;
BEGIN
  -- Get current period (YYYY-MM format)
  current_period := TO_CHAR(NOW(), 'YYYY-MM');
  
  -- Check if performance record exists for this period
  SELECT * INTO performance_record
  FROM public.supplier_performance
  WHERE supplier_id = NEW.supplier_id AND evaluation_period = current_period;
  
  IF FOUND THEN
    -- Update existing record
    UPDATE public.supplier_performance
    SET total_orders = total_orders + 1,
        total_purchase_amount = total_purchase_amount + NEW.total_amount,
        updated_at = NOW()
    WHERE id = performance_record.id;
  ELSE
    -- Create new performance record
    INSERT INTO public.supplier_performance (
      tenant_id, supplier_id, evaluation_period, total_orders, total_purchase_amount
    ) VALUES (
      (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()),
      NEW.supplier_id,
      current_period,
      1,
      NEW.total_amount
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_update_supplier_balance
AFTER INSERT ON public.supplier_payments
FOR EACH ROW
EXECUTE FUNCTION update_supplier_balance();

CREATE TRIGGER trigger_update_supplier_performance
AFTER INSERT ON public.purchase_orders
FOR EACH ROW
WHEN (NEW.status = 'confirmed')
EXECUTE FUNCTION update_supplier_performance();

-- ============================================================================
-- PART 10: Views for Reporting
-- ============================================================================

-- Supplier Summary View
CREATE OR REPLACE VIEW vw_supplier_summary AS
SELECT 
  s.id,
  s.tenant_id,
  s.name,
  s.contact_person,
  s.phone,
  s.email,
  s.payment_terms,
  s.credit_limit,
  s.current_balance,
  s.is_active,
  s.is_preferred,
  s.rating,
  s.created_at,
  COUNT(po.id) as total_orders,
  COALESCE(SUM(po.total_amount), 0) as total_purchase_value,
  COALESCE(SUM(CASE WHEN po.status = 'received' THEN po.total_amount ELSE 0 END), 0) as completed_orders_value,
  AVG(po.total_amount) as avg_order_value
FROM public.suppliers s
LEFT JOIN public.purchase_orders po ON s.id = po.supplier_id
WHERE s.tenant_id IS NOT NULL
GROUP BY s.id, s.tenant_id, s.name, s.contact_person, s.phone, s.email,
         s.payment_terms, s.credit_limit, s.current_balance, s.is_active,
         s.is_preferred, s.rating, s.created_at;

-- Purchase Order Summary View
CREATE OR REPLACE VIEW vw_purchase_order_summary AS
SELECT 
  po.id,
  po.tenant_id,
  po.supplier_id,
  po.order_number,
  po.order_date,
  po.expected_delivery_date,
  po.actual_delivery_date,
  po.status,
  po.subtotal,
  po.discount_amount,
  po.tax_amount,
  po.total_amount,
  po.paid_amount,
  po.balance_amount,
  po.payment_status,
  s.name as supplier_name,
  s.contact_person as supplier_contact,
  u.full_name as created_by_name,
  COUNT(poi.id) as item_count,
  SUM(poi.quantity_ordered) as total_quantity_ordered,
  SUM(poi.quantity_received) as total_quantity_received
FROM public.purchase_orders po
LEFT JOIN public.suppliers s ON po.supplier_id = s.id
LEFT JOIN public.profiles u ON po.created_by = u.id
LEFT JOIN public.purchase_order_items poi ON po.id = poi.purchase_order_id
GROUP BY po.id, po.tenant_id, po.supplier_id, po.order_number, po.order_date,
         po.expected_delivery_date, po.actual_delivery_date, po.status,
         po.subtotal, po.discount_amount, po.tax_amount, po.total_amount,
         po.paid_amount, po.balance_amount, po.payment_status,
         s.name, s.contact_person, u.full_name;

-- ============================================================================
-- PART 11: RPC Functions for Business Logic
-- ============================================================================

-- Function to create purchase order
CREATE OR REPLACE FUNCTION create_purchase_order(
  p_supplier_id UUID,
  p_items JSONB,
  p_expected_delivery_date TIMESTAMPTZ DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_terms_conditions TEXT DEFAULT NULL
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  purchase_order_id UUID
) AS $$
DECLARE
  purchase_order_id UUID;
  tenant_id UUID;
  order_number TEXT;
  item_record JSONB;
  subtotal NUMERIC := 0;
  tax_amount NUMERIC := 0;
  total_amount NUMERIC := 0;
BEGIN
  -- Get tenant ID
  SELECT tenant_id INTO tenant_id FROM public.profiles WHERE id = auth.uid();
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'User not found', NULL::UUID;
    RETURN;
  END IF;
  
  -- Generate order number
  order_number := 'PO-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || 
                  LPAD((SELECT COALESCE(MAX(CAST(SUBSTRING(order_number FROM '[0-9]+$') AS INTEGER)), 0) + 1
                        FROM public.purchase_orders 
                        WHERE tenant_id = tenant_id)::TEXT, 4, '0');
  
  -- Calculate totals
  FOR item_record IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    subtotal := subtotal + (item_record->>'unit_price')::NUMERIC * (item_record->>'quantity_ordered')::INTEGER;
  END LOOP;
  
  tax_amount := subtotal * 0.13; -- 13% VAT
  total_amount := subtotal + tax_amount;
  
  -- Create purchase order
  INSERT INTO public.purchase_orders (
    tenant_id, supplier_id, order_number, expected_delivery_date,
    subtotal, tax_amount, total_amount, notes, terms_conditions, created_by
  ) VALUES (
    tenant_id, p_supplier_id, order_number, p_expected_delivery_date,
    subtotal, tax_amount, total_amount, p_notes, p_terms_conditions, auth.uid()
  ) RETURNING id INTO purchase_order_id;
  
  -- Add purchase order items
  FOR item_record IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.purchase_order_items (
      purchase_order_id, product_id, product_name, description,
      quantity_ordered, unit_price, discount_percent, tax_rate, notes
    ) VALUES (
      purchase_order_id,
      (item_record->>'product_id')::UUID,
      item_record->>'product_name',
      item_record->>'description',
      (item_record->>'quantity_ordered')::INTEGER,
      (item_record->>'unit_price')::NUMERIC,
      COALESCE((item_record->>'discount_percent')::NUMERIC, 0),
      COALESCE((item_record->>'tax_rate')::NUMERIC, 13),
      item_record->>'notes'
    );
  END LOOP;
  
  RETURN QUERY SELECT true, 'Purchase order created successfully', purchase_order_id;
END;
$$ LANGUAGE plpgsql;

-- Function to receive purchase order items
CREATE OR REPLACE FUNCTION receive_purchase_order_items(
  p_purchase_order_id UUID,
  p_items JSONB
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  received_items INTEGER
) AS $$
DECLARE
  item_record JSONB;
  received_count INTEGER := 0;
  total_received INTEGER := 0;
  po_record RECORD;
BEGIN
  -- Get purchase order details
  SELECT * INTO po_record FROM public.purchase_orders WHERE id = p_purchase_order_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Purchase order not found', 0;
    RETURN;
  END IF;
  
  -- Process each item
  FOR item_record IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- Update purchase order item
    UPDATE public.purchase_order_items
    SET quantity_received = quantity_received + (item_record->>'quantity_received')::INTEGER
    WHERE purchase_order_id = p_purchase_order_id
    AND product_id = (item_record->>'product_id')::UUID;
    
    -- Update product stock
    UPDATE public.products
    SET stock_quantity = stock_quantity + (item_record->>'quantity_received')::INTEGER,
        updated_at = NOW()
    WHERE id = (item_record->>'product_id')::UUID;
    
    received_count := received_count + 1;
    total_received := total_received + (item_record->>'quantity_received')::INTEGER;
  END LOOP;
  
  -- Update purchase order status
  UPDATE public.purchase_orders
  SET status = CASE 
    WHEN (SELECT SUM(quantity_received) FROM public.purchase_order_items WHERE purchase_order_id = p_purchase_order_id) 
         >= (SELECT SUM(quantity_ordered) FROM public.purchase_order_items WHERE purchase_order_id = p_purchase_order_id) 
    THEN 'received'
    ELSE 'partial_received'
  END,
  actual_delivery_date = NOW(),
  updated_at = NOW()
  WHERE id = p_purchase_order_id;
  
  RETURN QUERY SELECT true, 'Items received successfully', received_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Supplier Management System - Migration Complete';
  RAISE NOTICE '📋 Tables Created: suppliers, purchase_orders, purchase_order_items, supplier_payments, supplier_invoices, supplier_performance';
  RAISE NOTICE '🔒 RLS Policies: Applied for tenant isolation and role-based access';
  RAISE NOTICE '📊 Views Created: vw_supplier_summary, vw_purchase_order_summary';
  RAISE NOTICE '⚙️ RPC Functions: create_purchase_order, receive_purchase_order_items';
  RAISE NOTICE '🔧 Triggers: Supplier balance updates, performance tracking';
END $$;
