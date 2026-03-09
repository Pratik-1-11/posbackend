-- Migration: Phase 1 - Returns & Exchange Management System
-- Purpose: Enable customer returns and exchanges with proper inventory restoration
-- Dependencies: Requires existing sales, products, customers, branches, tenants, and profiles tables

-- ============================================================================
-- PART 1: Create Missing Dependencies First
-- ============================================================================

-- Create tenants table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  domain TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create customers table if it doesn't exist (without tenant_id constraint first)
CREATE TABLE IF NOT EXISTS public.customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  email TEXT,
  address TEXT,
  city TEXT,
  pan_number TEXT,
  credit_limit NUMERIC(10, 2) DEFAULT 0,
  current_balance NUMERIC(10, 2) DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create branches table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.branches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  location TEXT,
  contact_number TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Add Multi-Tenant Support (if needed)
-- ============================================================================

-- Add tenant_id to branches if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
    ALTER TABLE public.branches ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
    RAISE NOTICE 'Added tenant_id to branches table';
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'customers' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
    ALTER TABLE public.customers ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
    RAISE NOTICE 'Added tenant_id to customers table';
  END IF;
END $$;

-- ============================================================================
-- PART 3: Returns Table (without foreign key constraints first)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.returns (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID,
  branch_id UUID,
  original_sale_id UUID,
  customer_id UUID,
  return_type TEXT CHECK (return_type IN ('refund', 'exchange', 'store_credit')) NOT NULL,
  return_reason TEXT NOT NULL,
  total_refund_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
  refund_method TEXT CHECK (refund_method IN ('cash', 'card', 'qr', 'store_credit')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'processed', 'cancelled')),
  notes TEXT,
  processed_by UUID,
  manager_approval BOOLEAN DEFAULT FALSE,
  manager_id UUID,
  manager_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  created_by UUID NOT NULL
);

-- ============================================================================
-- PART 4: Return Items Table (without foreign key constraints first)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.return_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  return_id UUID,
  product_id UUID NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(10, 2) NOT NULL,
  total_amount NUMERIC(10, 2) NOT NULL,
  reason TEXT,
  condition TEXT CHECK (condition IN ('new', 'used', 'damaged', 'defective')) DEFAULT 'used',
  restocked BOOLEAN DEFAULT FALSE,
  exchange_product_id UUID,
  restocked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 5: Exchange Transactions Table (without foreign key constraints first)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.exchange_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  return_id UUID NOT NULL,
  original_product_id UUID NOT NULL,
  exchange_product_id UUID NOT NULL,
  quantity INTEGER NOT NULL,
  price_difference NUMERIC(10, 2) NOT NULL DEFAULT 0,
  additional_payment NUMERIC(10, 2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 6: Return Policies Table (without foreign key constraints first)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.return_policies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID,
  name TEXT NOT NULL,
  description TEXT,
  return_period_days INTEGER DEFAULT 7,
  restocking_fee_percent NUMERIC(5, 2) DEFAULT 0,
  requires_original_receipt BOOLEAN DEFAULT TRUE,
  requires_manager_approval BOOLEAN DEFAULT FALSE,
  min_amount_for_approval NUMERIC(10, 2) DEFAULT 1000,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 7: Add Missing Columns and Foreign Key Constraints
-- ============================================================================

DO $$
BEGIN
  -- Ensure all required columns exist in returns table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'returns' AND table_schema = 'public') THEN
    -- Add missing columns if they don't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.returns ADD COLUMN tenant_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'branch_id') THEN
      ALTER TABLE public.returns ADD COLUMN branch_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'original_sale_id') THEN
      ALTER TABLE public.returns ADD COLUMN original_sale_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'customer_id') THEN
      ALTER TABLE public.returns ADD COLUMN customer_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'return_type') THEN
      ALTER TABLE public.returns ADD COLUMN return_type TEXT CHECK (return_type IN ('refund', 'exchange', 'store_credit')) NOT NULL DEFAULT 'refund';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'return_reason') THEN
      ALTER TABLE public.returns ADD COLUMN return_reason TEXT NOT NULL DEFAULT '';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'total_refund_amount') THEN
      ALTER TABLE public.returns ADD COLUMN total_refund_amount NUMERIC(10, 2) NOT NULL DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'refund_method') THEN
      ALTER TABLE public.returns ADD COLUMN refund_method TEXT CHECK (refund_method IN ('cash', 'card', 'qr', 'store_credit'));
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'status') THEN
      ALTER TABLE public.returns ADD COLUMN status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'processed', 'cancelled'));
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'notes') THEN
      ALTER TABLE public.returns ADD COLUMN notes TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'processed_by') THEN
      ALTER TABLE public.returns ADD COLUMN processed_by UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'manager_approval') THEN
      ALTER TABLE public.returns ADD COLUMN manager_approval BOOLEAN DEFAULT FALSE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'manager_id') THEN
      ALTER TABLE public.returns ADD COLUMN manager_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'manager_reason') THEN
      ALTER TABLE public.returns ADD COLUMN manager_reason TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'processed_at') THEN
      ALTER TABLE public.returns ADD COLUMN processed_at TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'created_by') THEN
      ALTER TABLE public.returns ADD COLUMN created_by UUID;
    END IF;
    
    RAISE NOTICE 'All required columns verified in returns table';
  END IF;
  
  -- Ensure all required columns exist in return_items table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'return_items' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'return_id') THEN
      ALTER TABLE public.return_items ADD COLUMN return_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'product_id') THEN
      ALTER TABLE public.return_items ADD COLUMN product_id UUID NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'quantity') THEN
      ALTER TABLE public.return_items ADD COLUMN quantity INTEGER NOT NULL CHECK (quantity > 0) DEFAULT 1;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'unit_price') THEN
      ALTER TABLE public.return_items ADD COLUMN unit_price NUMERIC(10, 2) NOT NULL DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'total_amount') THEN
      ALTER TABLE public.return_items ADD COLUMN total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'reason') THEN
      ALTER TABLE public.return_items ADD COLUMN reason TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'condition') THEN
      ALTER TABLE public.return_items ADD COLUMN condition TEXT CHECK (condition IN ('new', 'used', 'damaged', 'defective')) DEFAULT 'used';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'restocked') THEN
      ALTER TABLE public.return_items ADD COLUMN restocked BOOLEAN DEFAULT FALSE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'exchange_product_id') THEN
      ALTER TABLE public.return_items ADD COLUMN exchange_product_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'restocked_at') THEN
      ALTER TABLE public.return_items ADD COLUMN restocked_at TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_items' AND table_schema = 'public' AND column_name = 'created_at') THEN
      ALTER TABLE public.return_items ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    
    RAISE NOTICE 'All required columns verified in return_items table';
  END IF;
  
  -- Ensure all required columns exist in exchange_transactions table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'exchange_transactions' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'exchange_transactions' AND table_schema = 'public' AND column_name = 'return_id') THEN
      ALTER TABLE public.exchange_transactions ADD COLUMN return_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'exchange_transactions' AND table_schema = 'public' AND column_name = 'original_product_id') THEN
      ALTER TABLE public.exchange_transactions ADD COLUMN original_product_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'exchange_transactions' AND table_schema = 'public' AND column_name = 'exchange_product_id') THEN
      ALTER TABLE public.exchange_transactions ADD COLUMN exchange_product_id UUID;
    END IF;
    
    RAISE NOTICE 'All required columns verified in exchange_transactions table';
  END IF;
  
  -- Ensure all required columns exist in return_policies table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'return_policies' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'return_policies' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.return_policies ADD COLUMN tenant_id UUID;
    END IF;
    
    RAISE NOTICE 'All required columns verified in return_policies table';
  END IF;
  
  -- Now add foreign key constraints
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'returns' AND table_schema = 'public') THEN
    -- tenant_id constraint
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_tenant_id_fkey') THEN
      ALTER TABLE public.returns ADD CONSTRAINT returns_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
    END IF;
    
    -- branch_id constraint
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_branch_id_fkey') THEN
      ALTER TABLE public.returns ADD CONSTRAINT returns_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;
    END IF;
    
    -- original_sale_id constraint (only if sales table exists and column exists)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'sales' AND table_schema = 'public') THEN
      -- Check if original_sale_id column exists in returns table
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'original_sale_id') THEN
        -- Verify data types match
        IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_original_sale_id_fkey') THEN
          -- Check if both columns are UUID type
          DECLARE
            sales_uuid_count INTEGER;
            returns_uuid_count INTEGER;
          BEGIN
            SELECT COUNT(*) INTO sales_uuid_count
            FROM information_schema.columns 
            WHERE table_name = 'sales' AND table_schema = 'public' AND column_name = 'id' AND data_type = 'uuid';
            
            SELECT COUNT(*) INTO returns_uuid_count
            FROM information_schema.columns 
            WHERE table_name = 'returns' AND table_schema = 'public' AND column_name = 'original_sale_id' AND data_type = 'uuid';
            
            IF sales_uuid_count > 0 AND returns_uuid_count > 0 THEN
              ALTER TABLE public.returns ADD CONSTRAINT returns_original_sale_id_fkey FOREIGN KEY (original_sale_id) REFERENCES public.sales(id);
              RAISE NOTICE 'Foreign key constraint created for original_sale_id';
            ELSE
              RAISE NOTICE 'Data type mismatch: sales.id or returns.original_sale_id is not UUID (sales:%, returns:%)', sales_uuid_count, returns_uuid_count;
            END IF;
          END;
        END IF;
      ELSE
        RAISE NOTICE 'original_sale_id column does not exist in returns table';
      END IF;
    ELSE
      RAISE NOTICE 'sales table does not exist';
    END IF;
    
    -- customer_id constraint
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_customer_id_fkey') THEN
      ALTER TABLE public.returns ADD CONSTRAINT returns_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);
    END IF;
    
    -- processed_by constraint (only if profiles table exists)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'profiles' AND table_schema = 'public') THEN
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_processed_by_fkey') THEN
        ALTER TABLE public.returns ADD CONSTRAINT returns_processed_by_fkey FOREIGN KEY (processed_by) REFERENCES public.profiles(id);
      END IF;
      
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_manager_id_fkey') THEN
        ALTER TABLE public.returns ADD CONSTRAINT returns_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.profiles(id);
      END IF;
      
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'returns' AND constraint_name = 'returns_created_by_fkey') THEN
        ALTER TABLE public.returns ADD CONSTRAINT returns_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);
      END IF;
    END IF;
  END IF;
  
  -- Add foreign key constraints to return_items table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'return_items' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'return_items' AND constraint_name = 'return_items_return_id_fkey') THEN
      ALTER TABLE public.return_items ADD CONSTRAINT return_items_return_id_fkey FOREIGN KEY (return_id) REFERENCES public.returns(id) ON DELETE CASCADE;
    END IF;
    
    -- product_id constraints (only if products table exists)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products' AND table_schema = 'public') THEN
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'return_items' AND constraint_name = 'return_items_product_id_fkey') THEN
        ALTER TABLE public.return_items ADD CONSTRAINT return_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);
      END IF;
      
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'return_items' AND constraint_name = 'return_items_exchange_product_id_fkey') THEN
        ALTER TABLE public.return_items ADD CONSTRAINT return_items_exchange_product_id_fkey FOREIGN KEY (exchange_product_id) REFERENCES public.products(id);
      END IF;
    END IF;
  END IF;
  
  -- Add foreign key constraints to exchange_transactions table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'exchange_transactions' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'exchange_transactions' AND constraint_name = 'exchange_transactions_return_id_fkey') THEN
      ALTER TABLE public.exchange_transactions ADD CONSTRAINT exchange_transactions_return_id_fkey FOREIGN KEY (return_id) REFERENCES public.returns(id) ON DELETE CASCADE;
    END IF;
    
    -- product_id constraints (only if products table exists)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'products' AND table_schema = 'public') THEN
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'exchange_transactions' AND constraint_name = 'exchange_transactions_original_product_id_fkey') THEN
        ALTER TABLE public.exchange_transactions ADD CONSTRAINT exchange_transactions_original_product_id_fkey FOREIGN KEY (original_product_id) REFERENCES public.products(id);
      END IF;
      
      IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'exchange_transactions' AND constraint_name = 'exchange_transactions_exchange_product_id_fkey') THEN
        ALTER TABLE public.exchange_transactions ADD CONSTRAINT exchange_transactions_exchange_product_id_fkey FOREIGN KEY (exchange_product_id) REFERENCES public.products(id);
      END IF;
    END IF;
  END IF;
  
  -- Add foreign key constraints to return_policies table
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'return_policies' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'return_policies' AND constraint_name = 'return_policies_tenant_id_fkey') THEN
      ALTER TABLE public.return_policies ADD CONSTRAINT return_policies_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
    END IF;
  END IF;
  
  RAISE NOTICE 'All foreign key constraints added successfully';
END $$;

-- ============================================================================
-- PART 5: Indexes for Performance
-- ============================================================================

-- Returns table indexes
CREATE INDEX IF NOT EXISTS idx_returns_tenant ON public.returns(tenant_id);
CREATE INDEX IF NOT EXISTS idx_returns_branch ON public.returns(branch_id);
CREATE INDEX IF NOT EXISTS idx_returns_status ON public.returns(status);
CREATE INDEX IF NOT EXISTS idx_returns_customer ON public.returns(customer_id);
CREATE INDEX IF NOT EXISTS idx_returns_date ON public.returns(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_returns_original_sale ON public.returns(original_sale_id);

-- Return items indexes
CREATE INDEX IF NOT EXISTS idx_return_items_return ON public.return_items(return_id);
CREATE INDEX IF NOT EXISTS idx_return_items_product ON public.return_items(product_id);
CREATE INDEX IF NOT EXISTS idx_return_items_exchange ON public.return_items(exchange_product_id);

-- Exchange transactions indexes
CREATE INDEX IF NOT EXISTS idx_exchange_return ON public.exchange_transactions(return_id);
CREATE INDEX IF NOT EXISTS idx_exchange_products ON public.exchange_transactions(original_product_id, exchange_product_id);

-- ============================================================================
-- PART 6: Row Level Security (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.return_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exchange_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.return_policies ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Returns
CREATE POLICY "Users can view returns in their tenant" ON public.returns
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create returns in their branch" ON public.returns
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  branch_id = (SELECT branch_id FROM public.profiles WHERE id = auth.uid()) AND
  created_by = auth.uid()
);

CREATE POLICY "Managers can update returns" ON public.returns
FOR UPDATE USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  branch_id = (SELECT branch_id FROM public.profiles WHERE id = auth.uid()) AND
  (created_by = auth.uid() OR (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin'))
);

-- RLS Policies for Return Items
CREATE POLICY "Users can view return items via returns" ON public.return_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.returns r 
    WHERE r.id = return_id 
    AND r.tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
  )
);

CREATE POLICY "Users can manage return items" ON public.return_items
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.returns r 
    WHERE r.id = return_id 
    AND r.tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    AND (r.created_by = auth.uid() OR (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin'))
  )
);

-- RLS Policies for Exchange Transactions
CREATE POLICY "Users can view exchanges via returns" ON public.exchange_transactions
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.returns r 
    WHERE r.id = return_id 
    AND r.tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
  )
);

CREATE POLICY "Users can manage exchanges" ON public.exchange_transactions
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.returns r 
    WHERE r.id = return_id 
    AND r.tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
    AND (r.created_by = auth.uid() OR (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin'))
  )
);

-- RLS Policies for Return Policies
CREATE POLICY "Users can view policies in their tenant" ON public.return_policies
FOR SELECT USING (
  tenant_id IS NULL OR tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

CREATE POLICY "Admins can manage policies" ON public.return_policies
FOR ALL USING (
  CASE 
    WHEN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) IS NULL THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.profiles p 
      WHERE p.id = auth.uid() 
      AND p.role IN ('branch_admin', 'super_admin')
      AND p.tenant_id = public.return_policies.tenant_id
    ) THEN true
    ELSE false
  END
);

-- ============================================================================
-- PART 7: Database Functions and Triggers
-- ============================================================================

-- Function to validate return period
CREATE OR REPLACE FUNCTION validate_return_period()
RETURNS TRIGGER AS $$
DECLARE
  return_period INTEGER DEFAULT 7;
  days_since_sale INTEGER;
BEGIN
  -- Get return period from policy or use default
  SELECT COALESCE(rp.return_period_days, 7) INTO return_period
  FROM public.return_policies rp
  WHERE rp.tenant_id = NEW.tenant_id AND rp.is_active = true
  LIMIT 1;

  -- Calculate days since original sale
  SELECT EXTRACT(DAYS FROM (NEW.created_at - s.created_at)) INTO days_since_sale
  FROM public.sales s
  WHERE s.id = NEW.original_sale_id;

  -- Check if return is within allowed period
  IF days_since_sale > return_period THEN
    RAISE EXCEPTION 'Return period of % days exceeded. Sale was % days ago', return_period, days_since_sale;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle inventory restoration on return approval
CREATE OR REPLACE FUNCTION handle_return_inventory()
RETURNS TRIGGER AS $$
DECLARE
  return_item RECORD;
BEGIN
  -- Only process when status changes to 'approved' or 'processed'
  IF OLD.status = NEW.status OR NEW.status NOT IN ('approved', 'processed') THEN
    RETURN NEW;
  END IF;

  -- Restock items if they haven't been restocked yet
  FOR return_item IN 
    SELECT * FROM public.return_items WHERE return_id = NEW.id AND restocked = false
  LOOP
    -- Update product stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity + return_item.quantity,
        updated_at = NOW()
    WHERE id = return_item.product_id;

    -- Mark item as restocked
    UPDATE public.return_items 
    SET restocked = true, restocked_at = NOW()
    WHERE id = return_item.id;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_validate_return_period
BEFORE INSERT ON public.returns
FOR EACH ROW
EXECUTE FUNCTION validate_return_period();

CREATE TRIGGER trigger_handle_return_inventory
AFTER UPDATE ON public.returns
FOR EACH ROW
EXECUTE FUNCTION handle_return_inventory();

-- ============================================================================
-- PART 8: Views for Reporting
-- ============================================================================

-- Returns Summary View
CREATE OR REPLACE VIEW vw_returns_summary AS
SELECT 
  r.id,
  r.tenant_id,
  r.branch_id,
  r.original_sale_id,
  r.customer_id,
  r.return_type,
  r.return_reason,
  r.total_refund_amount,
  r.refund_method,
  r.status,
  r.created_at,
  r.processed_at,
  c.name as customer_name,
  c.phone as customer_phone,
  s.invoice_number as original_invoice,
  COUNT(ri.id) as item_count,
  SUM(ri.quantity) as total_quantity,
  u.full_name as created_by_name,
  p.full_name as processed_by_name
FROM public.returns r
LEFT JOIN public.customers c ON r.customer_id = c.id
LEFT JOIN public.sales s ON r.original_sale_id = s.id
LEFT JOIN public.return_items ri ON r.id = ri.return_id
LEFT JOIN public.profiles u ON r.created_by = u.id
LEFT JOIN public.profiles p ON r.processed_by = p.id
GROUP BY r.id, r.tenant_id, r.branch_id, r.original_sale_id, r.customer_id, 
         r.return_type, r.return_reason, r.total_refund_amount, r.refund_method,
         r.status, r.created_at, r.processed_at, c.name, c.phone, 
         s.invoice_number, u.full_name, p.full_name;

-- Return Items Detail View
CREATE OR REPLACE VIEW vw_return_items_detail AS
SELECT 
  ri.id,
  ri.return_id,
  ri.product_id,
  ri.quantity,
  ri.unit_price,
  ri.total_amount,
  ri.reason,
  ri.condition,
  ri.restocked,
  ri.exchange_product_id,
  ri.created_at,
  p.name as product_name,
  p.barcode as product_barcode,
  ep.name as exchange_product_name,
  ep.barcode as exchange_product_barcode,
  r.return_type,
  r.status as return_status
FROM public.return_items ri
LEFT JOIN public.products p ON ri.product_id = p.id
LEFT JOIN public.products ep ON ri.exchange_product_id = ep.id
LEFT JOIN public.returns r ON ri.return_id = r.id;

-- ============================================================================
-- PART 9: Default Return Policy
-- ============================================================================

-- Insert default return policy for existing tenants
INSERT INTO public.return_policies (tenant_id, name, description, return_period_days, restocking_fee_percent)
SELECT 
  id,
  'Standard Return Policy',
  'Standard 7-day return policy with manager approval required for amounts over Rs. 1000',
  7,
  0
FROM public.tenants
WHERE NOT EXISTS (
  SELECT 1 FROM public.return_policies WHERE tenant_id = tenants.id
);

-- If no tenants exist, create a default policy without tenant_id
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.return_policies LIMIT 1) THEN
    INSERT INTO public.return_policies (id, name, description, return_period_days, restocking_fee_percent, tenant_id)
    VALUES (
      uuid_generate_v4(),
      'Standard Return Policy',
      'Standard 7-day return policy with manager approval required for amounts over Rs. 1000',
      7,
      0,
      NULL
    );
  END IF;
END $$;

-- ============================================================================
-- PART 10: RPC Functions for Business Logic
-- ============================================================================

-- Function to process a return with inventory updates
CREATE OR REPLACE FUNCTION process_return(
  p_return_id UUID,
  p_processed_by UUID,
  p_status TEXT DEFAULT 'processed'
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  return_id UUID
) AS $$
DECLARE
  return_record RECORD;
  policy_record RECORD;
  requires_approval BOOLEAN DEFAULT FALSE;
BEGIN
  -- Get return details
  SELECT * INTO return_record FROM public.returns WHERE id = p_return_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Return not found', NULL::UUID;
    RETURN;
  END IF;

  -- Check if user has permission
  IF return_record.tenant_id != (SELECT tenant_id FROM public.profiles WHERE id = p_processed_by) THEN
    RETURN QUERY SELECT false, 'Unauthorized: Different tenant', NULL::UUID;
    RETURN;
  END IF;

  -- Get return policy
  SELECT * INTO policy_record FROM public.return_policies 
  WHERE tenant_id = return_record.tenant_id AND is_active = true 
  LIMIT 1;

  -- Check if manager approval is required
  requires_approval := COALESCE(policy_record.requires_manager_approval, false) OR 
                      (return_record.total_refund_amount >= COALESCE(policy_record.min_amount_for_approval, 1000));

  -- Validate approval requirements
  IF requires_approval AND NOT return_record.manager_approval THEN
    RETURN QUERY SELECT false, 'Manager approval required for this return', NULL::UUID;
    RETURN;
  END IF;

  -- Update return status
  UPDATE public.returns 
  SET status = p_status,
      processed_by = p_processed_by,
      processed_at = NOW()
  WHERE id = p_return_id;

  -- Log the action
  INSERT INTO public.audit_logs (tenant_id, user_id, action, table_name, record_id, details)
  VALUES (
    return_record.tenant_id,
    p_processed_by,
    'PROCESS_RETURN',
    'returns',
    p_return_id,
    json_build_object('status', p_status, 'refund_amount', return_record.total_refund_amount)
  );

  RETURN QUERY SELECT true, 'Return processed successfully', p_return_id;
END;
$$ LANGUAGE plpgsql;

-- Function to create exchange transaction
CREATE OR REPLACE FUNCTION create_exchange_transaction(
  p_return_id UUID,
  p_original_product_id UUID,
  p_exchange_product_id UUID,
  p_quantity INTEGER,
  p_price_difference NUMERIC(10, 2)
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT,
  exchange_id UUID
) AS $$
DECLARE
  return_record RECORD;
  original_product RECORD;
  exchange_product RECORD;
  exchange_id UUID;
BEGIN
  -- Validate return exists and is approved
  SELECT * INTO return_record FROM public.returns WHERE id = p_return_id;
  
  IF NOT FOUND OR return_record.status NOT IN ('approved', 'processed') THEN
    RETURN QUERY SELECT false, 'Return must be approved before creating exchange', NULL::UUID;
    RETURN;
  END IF;

  -- Get product details
  SELECT * INTO original_product FROM public.products WHERE id = p_original_product_id;
  SELECT * INTO exchange_product FROM public.products WHERE id = p_exchange_product_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Product not found', NULL::UUID;
    RETURN;
  END IF;

  -- Check exchange product stock
  IF exchange_product.stock_quantity < p_quantity THEN
    RETURN QUERY SELECT false, 'Insufficient stock for exchange product', NULL::UUID;
    RETURN;
  END IF;

  -- Create exchange transaction
  INSERT INTO public.exchange_transactions (
    return_id, original_product_id, exchange_product_id, quantity, price_difference
  ) VALUES (
    p_return_id, p_original_product_id, p_exchange_product_id, p_quantity, p_price_difference
  ) RETURNING id INTO exchange_id;

  -- Update inventory
  -- Add original product back to stock
  UPDATE public.products 
  SET stock_quantity = stock_quantity + p_quantity
  WHERE id = p_original_product_id;

  -- Remove exchange product from stock
  UPDATE public.products 
  SET stock_quantity = stock_quantity - p_quantity
  WHERE id = p_exchange_product_id;

  RETURN QUERY SELECT true, 'Exchange created successfully', exchange_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Returns & Exchange Management System - Migration Complete';
  RAISE NOTICE '📋 Tables Created: returns, return_items, exchange_transactions, return_policies';
  RAISE NOTICE '🔒 RLS Policies: Applied for tenant isolation and role-based access';
  RAISE NOTICE '📊 Views Created: vw_returns_summary, vw_return_items_detail';
  RAISE NOTICE '⚙️ RPC Functions: process_return, create_exchange_transaction';
  RAISE NOTICE '🔧 Triggers: Inventory restoration, return period validation';
END $$;
