-- Migration: Phase 1 - Low Stock Alert System
-- Purpose: Automated low stock notifications and inventory management
-- Dependencies: Requires existing products table

-- ============================================================================
-- PART 1: Stock Alerts Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.stock_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  branch_id UUID REFERENCES public.branches(id) NOT NULL,
  product_id UUID REFERENCES public.products(id) NOT NULL,
  alert_type TEXT CHECK (alert_type IN ('low_stock', 'out_of_stock', 'excess_stock', 'expiring_soon')) NOT NULL,
  current_stock INTEGER NOT NULL,
  min_stock_level INTEGER NOT NULL,
  max_stock_level INTEGER,
  alert_level TEXT CHECK (alert_level IN ('info', 'warning', 'critical')) NOT NULL,
  message TEXT NOT NULL,
  is_resolved BOOLEAN DEFAULT FALSE,
  resolved_by UUID REFERENCES public.profiles(id),
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,
  auto_generated BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Alert Subscriptions Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.alert_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  branch_id UUID REFERENCES public.branches(id),
  alert_type TEXT CHECK (alert_type IN ('low_stock', 'out_of_stock', 'excess_stock', 'expiring_soon', 'all')) NOT NULL,
  notification_method TEXT CHECK (notification_method IN ('email', 'sms', 'push', 'in_app')) NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  min_alert_level TEXT CHECK (min_alert_level IN ('info', 'warning', 'critical')) DEFAULT 'warning',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, user_id, branch_id, alert_type, notification_method)
);

-- ============================================================================
-- PART 3: Alert Notifications Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.alert_notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  stock_alert_id UUID REFERENCES public.stock_alerts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  notification_method TEXT CHECK (notification_method IN ('email', 'sms', 'push', 'in_app')) NOT NULL,
  recipient TEXT NOT NULL, -- Email address, phone number, or device token
  subject TEXT,
  message TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed', 'read')) NOT NULL,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  error_message TEXT,
  retry_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 4: Inventory Recommendations Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.inventory_recommendations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  branch_id UUID REFERENCES public.branches(id) NOT NULL,
  product_id UUID REFERENCES public.products(id) NOT NULL,
  recommendation_type TEXT CHECK (recommendation_type IN ('reorder', 'increase_stock', 'decrease_stock', 'discontinue')) NOT NULL,
  current_stock INTEGER NOT NULL,
  recommended_quantity INTEGER NOT NULL,
  recommended_action TEXT NOT NULL,
  priority TEXT CHECK (priority IN ('low', 'medium', 'high', 'urgent')) NOT NULL,
  reasoning TEXT NOT NULL,
  estimated_impact TEXT,
  cost_impact NUMERIC(12, 2),
  is_implemented BOOLEAN DEFAULT FALSE,
  implemented_by UUID REFERENCES public.profiles(id),
  implemented_at TIMESTAMPTZ,
  implementation_notes TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 5: Stock Movement History Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.stock_movements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  branch_id UUID REFERENCES public.branches(id) NOT NULL,
  product_id UUID REFERENCES public.products(id) NOT NULL,
  movement_type TEXT CHECK (movement_type IN ('sale', 'purchase', 'adjustment', 'return', 'transfer_in', 'transfer_out', 'damage', 'expiry')) NOT NULL,
  quantity_change INTEGER NOT NULL, -- Positive for increases, negative for decreases
  quantity_before INTEGER NOT NULL,
  quantity_after INTEGER NOT NULL,
  reference_id UUID, -- Links to sale, purchase, etc.
  reference_type TEXT, -- 'sale', 'purchase_order', 'return', etc.
  reason TEXT NOT NULL,
  cost_per_unit NUMERIC(10, 2),
  total_cost NUMERIC(12, 2),
  performed_by UUID REFERENCES public.profiles(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 5.5: Ensure All Required Columns Exist in All Tables
-- ============================================================================

DO $$
BEGIN
  -- Ensure stock_alerts table has all required columns
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stock_alerts' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'branch_id') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN branch_id UUID REFERENCES public.branches(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'product_id') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN product_id UUID REFERENCES public.products(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'alert_type') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN alert_type TEXT CHECK (alert_type IN ('low_stock', 'out_of_stock', 'excess_stock', 'expiring_soon')) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'current_stock') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN current_stock INTEGER NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'min_stock_level') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN min_stock_level INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'max_stock_level') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN max_stock_level INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'alert_level') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN alert_level TEXT CHECK (alert_level IN ('info', 'warning', 'critical')) DEFAULT 'warning';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'message') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN message TEXT NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'is_resolved') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN is_resolved BOOLEAN DEFAULT FALSE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'resolved_at') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN resolved_at TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'resolved_by') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN resolved_by UUID REFERENCES public.profiles(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'resolution_notes') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN resolution_notes TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'auto_generated') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN auto_generated BOOLEAN DEFAULT TRUE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'created_at') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_alerts' AND table_schema = 'public' AND column_name = 'updated_at') THEN
      ALTER TABLE public.stock_alerts ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
  END IF;
  
  -- Ensure alert_subscriptions table has all required columns
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'alert_subscriptions' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'user_id') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN user_id UUID REFERENCES public.profiles(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'branch_id') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN branch_id UUID REFERENCES public.branches(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'alert_type') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN alert_type TEXT CHECK (alert_type IN ('low_stock', 'out_of_stock', 'excess_stock', 'expiring_soon', 'all')) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'notification_method') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN notification_method TEXT CHECK (notification_method IN ('email', 'sms', 'push', 'in_app')) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'min_alert_level') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN min_alert_level TEXT CHECK (min_alert_level IN ('info', 'warning', 'critical')) DEFAULT 'warning';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'is_active') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'created_at') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_subscriptions' AND table_schema = 'public' AND column_name = 'updated_at') THEN
      ALTER TABLE public.alert_subscriptions ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
  END IF;
  
  -- Ensure alert_notifications table has all required columns
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'alert_notifications' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'stock_alert_id') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN stock_alert_id UUID REFERENCES public.stock_alerts(id) ON DELETE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'user_id') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN user_id UUID REFERENCES public.profiles(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'notification_method') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN notification_method TEXT CHECK (notification_method IN ('email', 'sms', 'push', 'in_app')) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'status') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'delivered'));
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'sent_at') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN sent_at TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'delivered_at') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN delivered_at TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'error_message') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN error_message TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'alert_notifications' AND table_schema = 'public' AND column_name = 'created_at') THEN
      ALTER TABLE public.alert_notifications ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
  END IF;
  
  -- Ensure stock_movements table has all required columns
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stock_movements' AND table_schema = 'public') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'tenant_id') THEN
      ALTER TABLE public.stock_movements ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'branch_id') THEN
      ALTER TABLE public.stock_movements ADD COLUMN branch_id UUID REFERENCES public.branches(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'product_id') THEN
      ALTER TABLE public.stock_movements ADD COLUMN product_id UUID REFERENCES public.products(id) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'movement_type') THEN
      ALTER TABLE public.stock_movements ADD COLUMN movement_type TEXT CHECK (movement_type IN ('sale', 'purchase', 'adjustment', 'return', 'transfer_in', 'transfer_out', 'damage', 'expiry')) NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'quantity_change') THEN
      ALTER TABLE public.stock_movements ADD COLUMN quantity_change INTEGER NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'quantity_before') THEN
      ALTER TABLE public.stock_movements ADD COLUMN quantity_before INTEGER NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'quantity_after') THEN
      ALTER TABLE public.stock_movements ADD COLUMN quantity_after INTEGER NOT NULL;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'reference_id') THEN
      ALTER TABLE public.stock_movements ADD COLUMN reference_id UUID;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'reference_type') THEN
      ALTER TABLE public.stock_movements ADD COLUMN reference_type TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'reason') THEN
      ALTER TABLE public.stock_movements ADD COLUMN reason TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'cost_per_unit') THEN
      ALTER TABLE public.stock_movements ADD COLUMN cost_per_unit NUMERIC(10, 2);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'total_cost') THEN
      ALTER TABLE public.stock_movements ADD COLUMN total_cost NUMERIC(12, 2);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'performed_by') THEN
      ALTER TABLE public.stock_movements ADD COLUMN performed_by UUID REFERENCES public.profiles(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'stock_movements' AND table_schema = 'public' AND column_name = 'created_at') THEN
      ALTER TABLE public.stock_movements ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
  END IF;
  
  RAISE NOTICE 'All required columns verified in alert system tables';
END $$;

-- ============================================================================
-- PART 6: Indexes for Performance
-- ============================================================================

-- Stock alerts indexes
CREATE INDEX IF NOT EXISTS idx_stock_alerts_tenant ON public.stock_alerts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_branch ON public.stock_alerts(branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_product ON public.stock_alerts(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_type ON public.stock_alerts(alert_type);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_level ON public.stock_alerts(alert_level);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_resolved ON public.stock_alerts(is_resolved);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_created ON public.stock_alerts(created_at DESC);

-- Alert subscriptions indexes
CREATE INDEX IF NOT EXISTS idx_alert_subscriptions_tenant ON public.alert_subscriptions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alert_subscriptions_user ON public.alert_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_alert_subscriptions_branch ON public.alert_subscriptions(branch_id);
CREATE INDEX IF NOT EXISTS idx_alert_subscriptions_type ON public.alert_subscriptions(alert_type);
CREATE INDEX IF NOT EXISTS idx_alert_subscriptions_active ON public.alert_subscriptions(is_active);

-- Alert notifications indexes
CREATE INDEX IF NOT EXISTS idx_alert_notifications_tenant ON public.alert_notifications(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alert_notifications_alert ON public.alert_notifications(stock_alert_id);
CREATE INDEX IF NOT EXISTS idx_alert_notifications_user ON public.alert_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_alert_notifications_status ON public.alert_notifications(status);
CREATE INDEX IF NOT EXISTS idx_alert_notifications_created ON public.alert_notifications(created_at DESC);

-- Inventory recommendations indexes
CREATE INDEX IF NOT EXISTS idx_inventory_recommendations_tenant ON public.inventory_recommendations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recommendations_branch ON public.inventory_recommendations(branch_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recommendations_product ON public.inventory_recommendations(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recommendations_type ON public.inventory_recommendations(recommendation_type);
CREATE INDEX IF NOT EXISTS idx_inventory_recommendations_priority ON public.inventory_recommendations(priority);
CREATE INDEX IF NOT EXISTS idx_inventory_recommendations_implemented ON public.inventory_recommendations(is_implemented);

-- Stock movements indexes
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant ON public.stock_movements(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_branch ON public.stock_movements(branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON public.stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_type ON public.stock_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_date ON public.stock_movements(created_at DESC);

-- ============================================================================
-- PART 7: Row Level Security (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.stock_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Stock Alerts
CREATE POLICY "Users can view stock alerts in their tenant" ON public.stock_alerts
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can manage stock alerts in their branch" ON public.stock_alerts
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  branch_id = (SELECT branch_id FROM public.profiles WHERE id = auth.uid())
);

-- RLS Policies for Alert Subscriptions
CREATE POLICY "Users can manage own alert subscriptions" ON public.alert_subscriptions
FOR ALL USING (user_id = auth.uid());

-- RLS Policies for Alert Notifications
CREATE POLICY "Users can view own alert notifications" ON public.alert_notifications
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "System can manage alert notifications" ON public.alert_notifications
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- RLS Policies for Inventory Recommendations
CREATE POLICY "Users can view inventory recommendations in their tenant" ON public.inventory_recommendations
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can manage recommendations in their branch" ON public.inventory_recommendations
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  branch_id = (SELECT branch_id FROM public.profiles WHERE id = auth.uid())
);

-- RLS Policies for Stock Movements
CREATE POLICY "Users can view stock movements in their tenant" ON public.stock_movements
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can create stock movements" ON public.stock_movements
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  performed_by = auth.uid()
);

-- ============================================================================
-- PART 8: Database Functions and Triggers
-- ============================================================================

-- Function to check and create stock alerts
CREATE OR REPLACE FUNCTION check_stock_alerts()
RETURNS TRIGGER AS $$
DECLARE
  alert_level TEXT;
  alert_message TEXT;
  alert_type TEXT;
  existing_alert RECORD;
BEGIN
  -- Determine alert type and level
  IF NEW.stock_quantity = 0 THEN
    alert_type := 'out_of_stock';
    alert_level := 'critical';
    alert_message := 'Product is completely out of stock';
  ELSIF NEW.stock_quantity <= NEW.min_stock_level THEN
    alert_type := 'low_stock';
    IF NEW.stock_quantity = 0 THEN
      alert_level := 'critical';
      alert_message := 'Product is out of stock';
    ELSIF NEW.stock_quantity <= NEW.min_stock_level * 0.5 THEN
      alert_level := 'critical';
      alert_message := 'Product stock is critically low';
    ELSE
      alert_level := 'warning';
      alert_message := 'Product stock is low';
    END IF;
  ELSIF NEW.max_stock_level IS NOT NULL AND NEW.stock_quantity >= NEW.max_stock_level THEN
    alert_type := 'excess_stock';
    alert_level := 'warning';
    alert_message := 'Product stock exceeds maximum level';
  ELSE
    -- No alert needed, resolve existing alerts if any
    UPDATE public.stock_alerts
    SET is_resolved = true, resolved_at = NOW(), resolved_by = auth.uid(),
        resolution_notes = 'Stock level normalized'
    WHERE product_id = NEW.id AND is_resolved = false;
    RETURN NEW;
  END IF;

  -- Check if alert already exists and is unresolved
  SELECT * INTO existing_alert
  FROM public.stock_alerts
  WHERE product_id = NEW.id AND alert_type = alert_type AND is_resolved = false;

  IF NOT FOUND THEN
    -- Create new alert
    INSERT INTO public.stock_alerts (
      tenant_id, branch_id, product_id, alert_type, current_stock,
      min_stock_level, max_stock_level, alert_level, message
    ) VALUES (
      (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()),
      (SELECT branch_id FROM public.profiles WHERE id = auth.uid()),
      NEW.id,
      alert_type,
      NEW.stock_quantity,
      NEW.min_stock_level,
      NEW.max_stock_level,
      alert_level,
      alert_message
    );
  ELSE
    -- Update existing alert
    UPDATE public.stock_alerts
    SET current_stock = NEW.stock_quantity,
        alert_level = alert_level,
        message = alert_message,
        created_at = NOW()
    WHERE id = existing_alert.id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to create stock movement record
CREATE OR REPLACE FUNCTION create_stock_movement()
RETURNS TRIGGER AS $$
DECLARE
  movement_type TEXT;
  reason TEXT;
  reference_id UUID;
  reference_type TEXT;
BEGIN
  -- Determine movement type based on context
  IF TG_OP = 'UPDATE' THEN
    movement_type := 'adjustment';
    reason := 'Stock quantity adjusted';
    reference_id := NULL;
    reference_type := 'manual_adjustment';
  ELSIF TG_OP = 'INSERT' THEN
    movement_type := 'purchase';
    reason := 'Stock increased from purchase';
    reference_id := NULL;
    reference_type := 'purchase_order';
  ELSE
    RETURN NULL;
  END IF;

  -- Create stock movement record
  INSERT INTO public.stock_movements (
    tenant_id, branch_id, product_id, movement_type,
    quantity_change, quantity_before, quantity_after,
    reference_id, reference_type, reason, performed_by
  ) VALUES (
    (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()),
    (SELECT branch_id FROM public.profiles WHERE id = auth.uid()),
    NEW.id,
    movement_type,
    COALESCE(NEW.stock_quantity, 0) - COALESCE(OLD.stock_quantity, 0),
    COALESCE(OLD.stock_quantity, 0),
    COALESCE(NEW.stock_quantity, 0),
    reference_id,
    reference_type,
    reason,
    auth.uid()
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Function to generate inventory recommendations
CREATE OR REPLACE FUNCTION generate_inventory_recommendations()
RETURNS TABLE (
  recommendation_count INTEGER,
  products_analyzed INTEGER
) AS $$
DECLARE
  recommendation_count INTEGER := 0;
  products_analyzed INTEGER := 0;
  product_record RECORD;
BEGIN
  -- Analyze each product for recommendations
  FOR product_record IN 
    SELECT p.*, b.name as branch_name
    FROM public.products p
    JOIN public.branches b ON p.branch_id = b.id
    WHERE p.is_active = true
  LOOP
    products_analyzed := products_analyzed + 1;

    -- Low stock recommendation
    IF product_record.stock_quantity <= product_record.min_stock_level THEN
      INSERT INTO public.inventory_recommendations (
        tenant_id, branch_id, product_id, recommendation_type,
        current_stock, recommended_quantity, recommended_action,
        priority, reasoning, cost_impact
      ) VALUES (
        product_record.tenant_id,
        product_record.branch_id,
        product_record.id,
        'reorder',
        product_record.stock_quantity,
        product_record.min_stock_level * 2, -- Recommended to double min stock
        'Reorder product immediately',
        CASE 
          WHEN product_record.stock_quantity = 0 THEN 'urgent'
          WHEN product_record.stock_quantity <= product_record.min_stock_level * 0.5 THEN 'high'
          ELSE 'medium'
        END,
        'Current stock is at or below minimum safe level',
        (product_record.min_stock_level * 2 - product_record.stock_quantity) * product_record.cost_price
      );
      recommendation_count := recommendation_count + 1;
    END IF;

    -- Excess stock recommendation
    IF product_record.max_stock_level IS NOT NULL 
       AND product_record.stock_quantity >= product_record.max_stock_level THEN
      INSERT INTO public.inventory_recommendations (
        tenant_id, branch_id, product_id, recommendation_type,
        current_stock, recommended_quantity, recommended_action,
        priority, reasoning, cost_impact
      ) VALUES (
        product_record.tenant_id,
        product_record.branch_id,
        product_record.id,
        'decrease_stock',
        product_record.stock_quantity,
        product_record.max_stock_level,
        'Consider promotion or discount to reduce excess stock',
        'medium',
        'Stock exceeds maximum optimal level',
        (product_record.stock_quantity - product_record.max_stock_level) * product_record.cost_price
      );
      recommendation_count := recommendation_count + 1;
    END IF;
  END LOOP;

  RETURN QUERY SELECT recommendation_count, products_analyzed;
END;
$$ LANGUAGE plpgsql;

-- Function to send alert notifications
CREATE OR REPLACE FUNCTION send_alert_notifications()
RETURNS TABLE (
  notifications_sent INTEGER
) AS $$
DECLARE
  notifications_sent INTEGER := 0;
  alert_record RECORD;
  subscription_record RECORD;
BEGIN
  -- Process each unresolved alert
  FOR alert_record IN 
    SELECT * FROM public.stock_alerts 
    WHERE is_resolved = false AND auto_generated = true
  LOOP
    -- Find subscribers for this alert type
    FOR subscription_record IN 
      SELECT * FROM public.alert_subscriptions 
      WHERE (alert_type = alert_record.alert_type OR alert_type = 'all')
        AND is_active = true
        AND tenant_id = alert_record.tenant_id
        AND (branch_id IS NULL OR branch_id = alert_record.branch_id)
    LOOP
      -- Create notification
      INSERT INTO public.alert_notifications (
        tenant_id, stock_alert_id, user_id, notification_method,
        recipient, subject, message
      ) VALUES (
        alert_record.tenant_id,
        alert_record.id,
        subscription_record.user_id,
        subscription_record.notification_method,
        COALESCE(
          (SELECT email FROM public.profiles WHERE id = subscription_record.user_id),
          (SELECT phone FROM public.profiles WHERE id = subscription_record.user_id)
        ),
        'Stock Alert: ' || alert_record.alert_type,
        alert_record.message
      );
      
      notifications_sent := notifications_sent + 1;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT notifications_sent;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER trigger_check_stock_alerts
AFTER UPDATE OF stock_quantity ON public.products
FOR EACH ROW
EXECUTE FUNCTION check_stock_alerts();

CREATE TRIGGER trigger_create_stock_movement_update
AFTER UPDATE ON public.products
FOR EACH ROW
WHEN (OLD.stock_quantity IS DISTINCT FROM NEW.stock_quantity)
EXECUTE FUNCTION create_stock_movement();

CREATE TRIGGER trigger_create_stock_movement_insert
AFTER INSERT ON public.products
FOR EACH ROW
EXECUTE FUNCTION create_stock_movement();

-- ============================================================================
-- PART 9: Views for Reporting
-- ============================================================================

-- Stock Alerts Summary View
CREATE OR REPLACE VIEW vw_stock_alerts_summary AS
SELECT 
  sa.id,
  sa.tenant_id,
  sa.branch_id,
  sa.product_id,
  sa.alert_type,
  sa.alert_level,
  sa.current_stock,
  sa.min_stock_level,
  sa.max_stock_level,
  sa.message,
  sa.is_resolved,
  sa.created_at,
  p.name as product_name,
  p.barcode,
  p.selling_price,
  b.name as branch_name,
  u.full_name as resolved_by_name
FROM public.stock_alerts sa
LEFT JOIN public.products p ON sa.product_id = p.id
LEFT JOIN public.branches b ON sa.branch_id = b.id
LEFT JOIN public.profiles u ON sa.resolved_by = u.id;

-- Inventory Recommendations View
CREATE OR REPLACE VIEW vw_inventory_recommendations AS
SELECT 
  ir.id,
  ir.tenant_id,
  ir.branch_id,
  ir.product_id,
  ir.recommendation_type,
  ir.current_stock,
  ir.recommended_quantity,
  ir.recommended_action,
  ir.priority,
  ir.reasoning,
  ir.estimated_impact,
  ir.cost_impact,
  ir.is_implemented,
  ir.created_at,
  p.name as product_name,
  p.barcode,
  p.cost_price,
  p.selling_price,
  b.name as branch_name
FROM public.inventory_recommendations ir
LEFT JOIN public.products p ON ir.product_id = p.id
LEFT JOIN public.branches b ON ir.branch_id = b.id;

-- Stock Movements Summary View
CREATE OR REPLACE VIEW vw_stock_movements_summary AS
SELECT 
  sm.id,
  sm.tenant_id,
  sm.branch_id,
  sm.product_id,
  sm.movement_type,
  sm.quantity_change,
  sm.quantity_before,
  sm.quantity_after,
  sm.reason,
  sm.cost_per_unit,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'stock_movements' 
      AND table_schema = 'public' 
      AND column_name = 'total_cost'
    ) THEN sm.total_cost
    ELSE NULL
  END as total_cost,
  sm.created_at,
  p.name as product_name,
  p.barcode,
  u.full_name as performed_by_name,
  b.name as branch_name
FROM public.stock_movements sm
LEFT JOIN public.products p ON sm.product_id = p.id
LEFT JOIN public.profiles u ON sm.performed_by = u.id
LEFT JOIN public.branches b ON sm.branch_id = b.id;

-- ============================================================================
-- PART 10: RPC Functions for Business Logic
-- ============================================================================

-- Function to get stock alerts with filters
CREATE OR REPLACE FUNCTION get_stock_alerts(
  p_tenant_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_alert_type TEXT DEFAULT NULL,
  p_alert_level TEXT DEFAULT NULL,
  p_is_resolved BOOLEAN DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
  id UUID,
  product_id UUID,
  product_name TEXT,
  alert_type TEXT,
  alert_level TEXT,
  current_stock INTEGER,
  min_stock_level INTEGER,
  message TEXT,
  is_resolved BOOLEAN,
  created_at TIMESTAMPTZ,
  branch_name TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    sa.id,
    sa.product_id,
    p.name as product_name,
    sa.alert_type,
    sa.alert_level,
    sa.current_stock,
    sa.min_stock_level,
    sa.message,
    sa.is_resolved,
    sa.created_at,
    b.name as branch_name
  FROM public.stock_alerts sa
  JOIN public.products p ON sa.product_id = p.id
  JOIN public.branches b ON sa.branch_id = b.id
  WHERE sa.tenant_id = p_tenant_id
    AND (p_branch_id IS NULL OR sa.branch_id = p_branch_id)
    AND (p_alert_type IS NULL OR sa.alert_type = p_alert_type)
    AND (p_alert_level IS NULL OR sa.alert_level = p_alert_level)
    AND (p_is_resolved IS NULL OR sa.is_resolved = p_is_resolved)
  ORDER BY sa.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve stock alert
CREATE OR REPLACE FUNCTION resolve_stock_alert(
  p_alert_id UUID,
  p_resolution_notes TEXT DEFAULT NULL
) RETURNS TABLE (
  success BOOLEAN,
  message TEXT
) AS $$
DECLARE
  alert_record RECORD;
BEGIN
  -- Get alert details
  SELECT * INTO alert_record FROM public.stock_alerts WHERE id = p_alert_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Alert not found';
    RETURN;
  END IF;
  
  -- Check if user has permission
  IF alert_record.tenant_id != (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) THEN
    RETURN QUERY SELECT false, 'Unauthorized';
    RETURN;
  END IF;
  
  -- Resolve alert
  UPDATE public.stock_alerts
  SET is_resolved = true,
      resolved_by = auth.uid(),
      resolved_at = NOW(),
      resolution_notes = p_resolution_notes
  WHERE id = p_alert_id;
  
  RETURN QUERY SELECT true, 'Alert resolved successfully';
END;
$$ LANGUAGE plpgsql;

-- Function to get inventory recommendations
CREATE OR REPLACE FUNCTION get_inventory_recommendations(
  p_tenant_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_recommendation_type TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT NULL,
  p_is_implemented BOOLEAN DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
) RETURNS TABLE (
  id UUID,
  product_id UUID,
  product_name TEXT,
  recommendation_type TEXT,
  current_stock INTEGER,
  recommended_quantity INTEGER,
  recommended_action TEXT,
  priority TEXT,
  reasoning TEXT,
  cost_impact NUMERIC(12, 2),
  is_implemented BOOLEAN,
  created_at TIMESTAMPTZ,
  branch_name TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ir.id,
    ir.product_id,
    p.name as product_name,
    ir.recommendation_type,
    ir.current_stock,
    ir.recommended_quantity,
    ir.recommended_action,
    ir.priority,
    ir.reasoning,
    ir.cost_impact,
    ir.is_implemented,
    ir.created_at,
    b.name as branch_name
  FROM public.inventory_recommendations ir
  JOIN public.products p ON ir.product_id = p.id
  JOIN public.branches b ON ir.branch_id = b.id
  WHERE ir.tenant_id = p_tenant_id
    AND (p_branch_id IS NULL OR ir.branch_id = p_branch_id)
    AND (p_recommendation_type IS NULL OR ir.recommendation_type = p_recommendation_type)
    AND (p_priority IS NULL OR ir.priority = p_priority)
    AND (p_is_implemented IS NULL OR ir.is_implemented = p_is_implemented)
    AND (ir.expires_at IS NULL OR ir.expires_at > NOW())
  ORDER BY 
    CASE ir.priority 
      WHEN 'urgent' THEN 1 
      WHEN 'high' THEN 2 
      WHEN 'medium' THEN 3 
      WHEN 'low' THEN 4 
    END,
    ir.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Low Stock Alert System - Migration Complete';
  RAISE NOTICE '📋 Tables Created: stock_alerts, alert_subscriptions, alert_notifications, inventory_recommendations, stock_movements';
  RAISE NOTICE '🔒 RLS Policies: Applied for tenant isolation and role-based access';
  RAISE NOTICE '📊 Views Created: vw_stock_alerts_summary, vw_inventory_recommendations, vw_stock_movements_summary';
  RAISE NOTICE '⚙️ RPC Functions: get_stock_alerts, resolve_stock_alert, get_inventory_recommendations';
  RAISE NOTICE '🔧 Triggers: Stock alert creation, stock movement tracking';
  RAISE NOTICE '📈 Automated Features: Alert generation, inventory recommendations, notification system';
END $$;
