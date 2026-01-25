-- ==========================================
-- MULTI-STORE & SUBSCRIPTION SYSTEM
-- Version: 1.0
-- ==========================================

-- 1. Create Tenant Upgrade Requests Table
CREATE TABLE IF NOT EXISTS public.tenant_upgrade_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  
  -- Request Details
  requested_tier TEXT NOT NULL CHECK (requested_tier IN ('pro', 'enterprise')),
  current_tier TEXT NOT NULL,
  requested_stores_count INTEGER,
  business_justification TEXT,
  
  -- Status tracking
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Add New Columns to Tenants for Store Management
DO $$
BEGIN
  -- Multi-store capacity tracking
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tenants' AND column_name = 'max_stores') THEN
    ALTER TABLE public.tenants ADD COLUMN max_stores INTEGER DEFAULT 1;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tenants' AND column_name = 'current_stores_count') THEN
    ALTER TABLE public.tenants ADD COLUMN current_stores_count INTEGER DEFAULT 0;
  END IF;

  -- Verification status
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tenants' AND column_name = 'verified') THEN
    ALTER TABLE public.tenants ADD COLUMN verified BOOLEAN DEFAULT FALSE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tenants' AND column_name = 'verified_at') THEN
    ALTER TABLE public.tenants ADD COLUMN verified_at TIMESTAMPTZ;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tenants' AND column_name = 'verified_by') THEN
    ALTER TABLE public.tenants ADD COLUMN verified_by UUID REFERENCES public.profiles(id);
  END IF;
END $$;

-- 3. Enhance Branches Table
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND column_name = 'is_active') THEN
    ALTER TABLE public.branches ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND column_name = 'manager_id') THEN
    ALTER TABLE public.branches ADD COLUMN manager_id UUID REFERENCES public.profiles(id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND column_name = 'address') THEN
    ALTER TABLE public.branches ADD COLUMN address TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND column_name = 'phone') THEN
    ALTER TABLE public.branches ADD COLUMN phone TEXT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND column_name = 'email') THEN
    ALTER TABLE public.branches ADD COLUMN email TEXT;
  END IF;
END $$;

-- 4. Create Store Inventory Tracking (Branch-wise Stock)
-- This table tracks how much of each product is in which branch
CREATE TABLE IF NOT EXISTS public.branch_inventory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES public.products(id) ON DELETE CASCADE,
  
  quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  min_quantity INTEGER DEFAULT 5,
  shelf_location TEXT,
  
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(branch_id, product_id)
);

-- 5. Create Stock Transfers Table
CREATE TABLE IF NOT EXISTS public.stock_transfers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  
  from_branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
  to_branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
  
  product_id INTEGER REFERENCES public.products(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'transit', 'completed', 'cancelled')),
  notes TEXT,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_branch_inventory_branch ON public.branch_inventory(branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_inventory_product ON public.branch_inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_upgrade_requests_tenant ON public.tenant_upgrade_requests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_upgrade_requests_status ON public.tenant_upgrade_requests(status);

-- 7. RLS Policies for the new tables
ALTER TABLE public.tenant_upgrade_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;

-- 7.1 Upgrade Requests RLS
CREATE POLICY "Tenants can see their own upgrade requests" ON public.tenant_upgrade_requests
  FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Tenants can create their own upgrade requests" ON public.tenant_upgrade_requests
  FOR INSERT WITH CHECK (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- 7.2 Branch Inventory RLS
CREATE POLICY "Tenants can manage their branch inventory" ON public.branch_inventory
  FOR ALL USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- 7.3 Stock Transfers RLS
CREATE POLICY "Tenants can view their stock transfers" ON public.stock_transfers
  FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Tenants can create stock transfers" ON public.stock_transfers
  FOR INSERT WITH CHECK (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- 7.4 Super Admin Override (Assuming SUPER_ADMIN role exists)
CREATE POLICY "Super admins can see all upgrade requests" ON public.tenant_upgrade_requests
  FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('SUPER_ADMIN', 'super_admin')));
-- 8. Stored Procedure for Branch-Specific Stock Adjustment
CREATE OR REPLACE FUNCTION public.adjust_branch_stock(
  p_tenant_id UUID,
  p_branch_id UUID,
  p_product_id INTEGER,
  p_user_id UUID,
  p_quantity INTEGER,
  p_type TEXT, -- 'in', 'out', 'adjustment'
  p_reason TEXT DEFAULT 'Manual Adjustment'
) RETURNS TABLE (new_stock INTEGER, movement_id UUID) AS $$
DECLARE
  v_new_quantity INTEGER;
  v_movement_id UUID;
  v_current_quantity INTEGER;
BEGIN
  -- 1. Ensure branch inventory record exists
  INSERT INTO public.branch_inventory (tenant_id, branch_id, product_id, quantity)
  VALUES (p_tenant_id, p_branch_id, p_product_id, 0)
  ON CONFLICT (branch_id, product_id) DO NOTHING;

  -- 2. Get current quantity
  SELECT quantity INTO v_current_quantity FROM public.branch_inventory
  WHERE branch_id = p_branch_id AND product_id = p_product_id;

  -- 3. Calculate new quantity
  IF p_type = 'in' THEN
    v_new_quantity := v_current_quantity + p_quantity;
  ELSIF p_type = 'out' THEN
    v_new_quantity := v_current_quantity - p_quantity;
    IF v_new_quantity < 0 THEN
      RAISE EXCEPTION 'Insufficient stock in this branch';
    END IF;
  ELSE -- adjustment
    v_new_quantity := p_quantity;
  END IF;

  -- 4. Update branch inventory
  UPDATE public.branch_inventory
  SET quantity = v_new_quantity, updated_at = NOW()
  WHERE branch_id = p_branch_id AND product_id = p_product_id;

  -- 5. Log movement
  INSERT INTO public.inventory_movements (
    tenant_id, product_id, user_id, type, quantity, 
    old_stock, new_stock, reason, created_at
  )
  VALUES (
    p_tenant_id, p_product_id, p_user_id, p_type, p_quantity,
    v_current_quantity, v_new_quantity, p_reason || ' (Branch: ' || p_branch_id || ')', NOW()
  ) RETURNING id INTO v_movement_id;

  -- 6. Update global product stock rollup (optional but helpful)
  UPDATE public.products
  SET stock_quantity = (SELECT SUM(quantity) FROM public.branch_inventory WHERE product_id = p_product_id)
  WHERE id = p_product_id;

  RETURN QUERY SELECT v_new_quantity, v_movement_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
