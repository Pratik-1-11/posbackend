-- Migration: Phase 2 - Advanced Inventory Management
-- Purpose: Implement batch tracking, expiry management, and automated reordering
-- Dependencies: Requires basic inventory system from Phase 1

-- ============================================================================
-- PART 1: Batch Tracking System
-- ============================================================================

-- Product Batches Table
CREATE TABLE IF NOT EXISTS public.product_batches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  batch_number TEXT NOT NULL,
  supplier_id UUID REFERENCES public.suppliers(id),
  supplier_batch_number TEXT,
  manufacture_date DATE,
  expiry_date DATE,
  quantity_received INTEGER NOT NULL CHECK (quantity_received > 0),
  quantity_remaining INTEGER NOT NULL CHECK (quantity_remaining >= 0),
  quantity_sold INTEGER DEFAULT 0 CHECK (quantity_sold >= 0),
  quantity_wasted INTEGER DEFAULT 0 CHECK (quantity_wasted >= 0),
  unit_cost NUMERIC(10, 2) NOT NULL,
  unit_price NUMERIC(10, 2) NOT NULL,
  batch_status TEXT DEFAULT 'active' CHECK (batch_status IN ('active', 'depleted', 'expired', 'recalled', 'quarantined')),
  storage_location TEXT,
  storage_conditions TEXT, -- Temperature, humidity requirements
  quality_grade TEXT CHECK (quality_grade IN ('A', 'B', 'C', 'reject')),
  certification_numbers TEXT[], -- Quality certifications
  notes TEXT,
  received_by UUID NOT NULL REFERENCES public.profiles(id),
  received_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, branch_id, product_id, batch_number),
  CHECK (quantity_received >= quantity_sold + quantity_wasted + quantity_remaining)
);

-- Batch Transactions Table
CREATE TABLE IF NOT EXISTS public.batch_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  batch_id UUID NOT NULL REFERENCES public.product_batches(id) ON DELETE CASCADE,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('receive', 'sale', 'return', 'waste', 'transfer_out', 'transfer_in', 'adjustment')),
  quantity INTEGER NOT NULL,
  unit_cost NUMERIC(10, 2),
  total_cost NUMERIC(12, 2),
  reference_id UUID, -- Reference to sale, purchase, or adjustment
  reference_type TEXT, -- 'sale', 'purchase', 'return', 'adjustment', 'transfer'
  reason TEXT,
  performed_by UUID NOT NULL REFERENCES public.profiles(id),
  performed_at TIMESTAMPTZ DEFAULT NOW(),
  quantity_before INTEGER NOT NULL,
  quantity_after INTEGER NOT NULL
);

-- Batch Quality Control Table
CREATE TABLE IF NOT EXISTS public.batch_quality_control (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  batch_id UUID NOT NULL REFERENCES public.product_batches(id) ON DELETE CASCADE,
  inspection_date DATE NOT NULL,
  inspection_type TEXT NOT NULL CHECK (inspection_type IN ('incoming', 'periodic', 'random', 'complaint_related')),
  inspector_id UUID NOT NULL REFERENCES public.profiles(id),
  quality_score NUMERIC(5, 2) CHECK (quality_score >= 0 AND quality_score <= 100),
  passed_inspection BOOLEAN NOT NULL,
  issues_found TEXT,
  corrective_actions TEXT,
  follow_up_required BOOLEAN DEFAULT FALSE,
  follow_up_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Expiry Management System
-- ============================================================================

-- Expiry Tracking Table
CREATE TABLE IF NOT EXISTS public.expiry_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id),
  batch_id UUID REFERENCES public.product_batches(id),
  expiry_date DATE NOT NULL,
  days_to_expiry INTEGER GENERATED ALWAYS AS (expiry_date - CURRENT_DATE) STORED,
  quantity_at_risk INTEGER DEFAULT 0,
  expiry_status TEXT GENERATED ALWAYS AS (
    CASE 
      WHEN expiry_date < CURRENT_DATE THEN 'expired'
      WHEN expiry_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'critical'
      WHEN expiry_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'warning'
      WHEN expiry_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'monitor'
      ELSE 'safe'
    END
  ) STORED,
  last_checked_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, branch_id, product_id, batch_id, expiry_date)
);

-- Expiry Alerts Table
CREATE TABLE IF NOT EXISTS public.expiry_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  expiry_tracking_id UUID NOT NULL REFERENCES public.expiry_tracking(id) ON DELETE CASCADE,
  alert_type TEXT NOT NULL CHECK (alert_type IN ('expiring_soon', 'expired', 'quantity_at_risk')),
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  message TEXT NOT NULL,
  quantity_affected INTEGER DEFAULT 0,
  estimated_loss NUMERIC(12, 2) DEFAULT 0,
  recommended_action TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'acknowledged', 'resolved', 'dismissed')),
  acknowledged_by UUID REFERENCES public.profiles(id),
  acknowledged_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES public.profiles(id),
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Expiry Actions Table
CREATE TABLE IF NOT EXISTS public.expiry_actions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  expiry_alert_id UUID REFERENCES public.expiry_alerts(id) ON DELETE CASCADE,
  batch_id UUID NOT NULL REFERENCES public.product_batches(id) ON DELETE CASCADE,
  action_type TEXT NOT NULL CHECK (action_type IN ('discount', 'promotion', 'return_to_supplier', 'dispose', 'donate', 'relabel')),
  quantity INTEGER NOT NULL,
  discount_percentage NUMERIC(5, 2),
  action_reason TEXT,
  performed_by UUID NOT NULL REFERENCES public.profiles(id),
  performed_at TIMESTAMPTZ DEFAULT NOW(),
  expected_recovery NUMERIC(12, 2) DEFAULT 0,
  actual_recovery NUMERIC(12, 2) DEFAULT 0,
  notes TEXT
);

-- ============================================================================
-- PART 3: Automated Reordering System
-- ============================================================================

-- Reorder Rules Table
CREATE TABLE IF NOT EXISTS public.reorder_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE, -- NULL for tenant-wide rules
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE, -- NULL for category-wide rules
  product_category TEXT, -- For category-wide rules
  rule_type TEXT NOT NULL CHECK (rule_type IN ('stock_level', 'time_based', 'demand_based', 'seasonal')),
  trigger_condition JSONB NOT NULL, -- Flexible trigger conditions
  reorder_quantity_formula TEXT, -- SQL formula for calculating reorder quantity
  min_reorder_quantity INTEGER DEFAULT 1,
  max_reorder_quantity INTEGER,
  lead_time_days INTEGER DEFAULT 7,
  safety_stock_percentage NUMERIC(5, 2) DEFAULT 20,
  max_order_value NUMERIC(12, 2),
  preferred_supplier_id UUID REFERENCES public.suppliers(id),
  auto_approve BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (product_id IS NOT NULL OR product_category IS NOT NULL)
);

-- Reorder Suggestions Table
CREATE TABLE IF NOT EXISTS public.reorder_suggestions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  rule_id UUID REFERENCES public.reorder_rules(id),
  suggestion_type TEXT NOT NULL CHECK (suggestion_type IN ('stock_level', 'expiry_risk', 'demand_spike', 'seasonal')),
  current_stock INTEGER NOT NULL,
  suggested_quantity INTEGER NOT NULL,
  suggested_unit_cost NUMERIC(10, 2),
  total_suggested_cost NUMERIC(12, 2),
  urgency_level TEXT CHECK (urgency_level IN ('low', 'medium', 'high', 'critical')),
  reason TEXT NOT NULL,
  expected_delivery_date DATE,
  confidence_score NUMERIC(5, 2) CHECK (confidence_score >= 0 AND confidence_score <= 100),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'ordered', 'received')),
  approved_by UUID REFERENCES public.profiles(id),
  approved_at TIMESTAMPTZ,
  rejected_by UUID REFERENCES public.profiles(id),
  rejected_at TIMESTAMPTZ,
  rejection_reason TEXT,
  ordered_by UUID REFERENCES public.profiles(id),
  ordered_at TIMESTAMPTZ,
  purchase_order_id UUID REFERENCES public.purchase_orders(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Purchase Orders Table (Enhanced for advanced inventory)
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  supplier_id UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
  order_number TEXT UNIQUE NOT NULL,
  order_date DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_delivery_date DATE,
  actual_delivery_date DATE,
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'confirmed', 'partial_received', 'received', 'cancelled')),
  total_amount NUMERIC(12, 2) DEFAULT 0,
  tax_amount NUMERIC(12, 2) DEFAULT 0,
  discount_amount NUMERIC(12, 2) DEFAULT 0,
  net_amount NUMERIC(12, 2) DEFAULT 0,
  payment_terms TEXT DEFAULT 'NET 30',
  delivery_terms TEXT,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  approved_by UUID REFERENCES public.profiles(id),
  approved_at TIMESTAMPTZ,
  received_by UUID REFERENCES public.profiles(id),
  received_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Purchase Order Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id),
  quantity_ordered INTEGER NOT NULL CHECK (quantity_ordered > 0),
  quantity_received INTEGER DEFAULT 0 CHECK (quantity_received >= 0),
  unit_price NUMERIC(10, 2) NOT NULL,
  total_amount NUMERIC(12, 2) NOT NULL,
  discount_percentage NUMERIC(5, 2) DEFAULT 0,
  tax_percentage NUMERIC(5, 2) DEFAULT 0,
  expected_unit_cost NUMERIC(10, 2),
  batch_number TEXT,
  expiry_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (quantity_received <= quantity_ordered)
);

-- ============================================================================
-- PART 4: Inventory Optimization Functions
-- ============================================================================

-- Function to calculate optimal reorder quantity
CREATE OR REPLACE FUNCTION calculate_optimal_reorder_quantity(
  p_tenant_id UUID,
  p_branch_id UUID,
  p_product_id UUID,
  p_lead_time_days INTEGER DEFAULT 7,
  p_service_level NUMERIC DEFAULT 0.95
)
RETURNS TABLE (
  current_stock INTEGER,
  daily_usage NUMERIC,
  safety_stock INTEGER,
  reorder_point INTEGER,
  optimal_quantity INTEGER,
  total_cost NUMERIC,
  reasoning TEXT
) AS $$
DECLARE
  usage_data RECORD;
  optimal_qty INTEGER;
  safety_stock_calc INTEGER;
  reorder_point_calc INTEGER;
BEGIN
  -- Get usage statistics
  SELECT 
    COALESCE(p.stock_quantity, 0) as current_stock,
    COALESCE(AVG(daily_usage.daily_qty), 0) as avg_daily_usage,
    COALESCE(STDDEV(daily_usage.daily_qty), 0) as std_dev_usage
  INTO usage_data
  FROM public.products p
  LEFT JOIN (
    SELECT 
      si.product_id,
      DATE(si.created_at) as usage_date,
      SUM(si.quantity) as daily_qty
    FROM public.sale_items si
    LEFT JOIN public.sales s ON si.sale_id = s.id
    WHERE s.status = 'completed'
      AND s.branch_id = p_branch_id
      AND si.created_at >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY si.product_id, DATE(si.created_at)
  ) daily_usage ON p.id = daily_usage.product_id
  WHERE p.id = p_product_id AND p.branch_id = p_branch_id
  GROUP BY p.stock_quantity;
  
  -- Calculate safety stock using service level
  safety_stock_calc := CEIL(usage_data.std_dev_usage * p_lead_time_days * 
                          CASE p_service_level
                            WHEN 0.90 THEN 1.28
                            WHEN 0.95 THEN 1.65
                            WHEN 0.99 THEN 2.33
                            ELSE 1.65
                          END);
  
  -- Calculate reorder point
  reorder_point_calc := CEIL(usage_data.avg_daily_usage * p_lead_time_days) + safety_stock_calc;
  
  -- Calculate optimal reorder quantity (EOQ simplified)
  optimal_qty := CEIL(GREATEST(
    reorder_point_calc - usage_data.current_stock,
    CEIL(SQRT(2 * usage_data.avg_daily_usage * 30 * 50 / COALESCE(p.cost_price, 1))) -- Simplified EOQ
  ));
  
  RETURN QUERY
  SELECT 
    usage_data.current_stock,
    usage_data.avg_daily_usage,
    safety_stock_calc,
    reorder_point_calc,
    optimal_qty,
    optimal_qty * COALESCE(p.cost_price, 1),
    'Based on ' || p_lead_time_days || ' days lead time and ' || (p_service_level * 100) || '% service level' as reasoning
  FROM public.products p
  WHERE p.id = p_product_id AND p.branch_id = p_branch_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check expiry and create alerts
CREATE OR REPLACE FUNCTION check_expiry_alerts()
RETURNS INTEGER AS $$
DECLARE
  alert_count INTEGER := 0;
  expiry_record RECORD;
  alert_id UUID;
BEGIN
  -- Check for expiring products
  FOR expiry_record IN 
    SELECT 
      et.id,
      et.tenant_id,
      et.branch_id,
      et.product_id,
      et.batch_id,
      et.expiry_date,
      et.days_to_expiry,
      COALESCE(SUM(pb.quantity_remaining), 0) as total_quantity,
      p.name as product_name,
      p.cost_price
    FROM public.expiry_tracking et
    LEFT JOIN public.product_batches pb ON et.batch_id = pb.id
    LEFT JOIN public.products p ON et.product_id = p.id AND et.branch_id = p.branch_id
    WHERE et.days_to_expiry <= 30
      AND et.days_to_expiry >= -30 -- Only last 30 days expired
      AND et.expiry_status IN ('critical', 'warning', 'expired')
    GROUP BY et.id, et.tenant_id, et.branch_id, et.product_id, et.batch_id, 
             et.expiry_date, et.days_to_expiry, p.name, p.cost_price
  LOOP
    -- Create alert if not exists
    IF NOT EXISTS (
      SELECT 1 FROM public.expiry_alerts ea 
      WHERE ea.expiry_tracking_id = expiry_record.id 
        AND ea.status = 'active'
    ) THEN
      INSERT INTO public.expiry_alerts (
        tenant_id, expiry_tracking_id, alert_type, severity, 
        message, quantity_affected, estimated_loss
      ) VALUES (
        expiry_record.tenant_id,
        expiry_record.id,
        CASE 
          WHEN expiry_record.days_to_expiry < 0 THEN 'expired'
          WHEN expiry_record.days_to_expiry <= 7 THEN 'expiring_soon'
          ELSE 'expiring_soon'
        END,
        CASE 
          WHEN expiry_record.days_to_expiry < 0 THEN 'critical'
          WHEN expiry_record.days_to_expiry <= 7 THEN 'high'
          ELSE 'medium'
        END,
        CASE 
          WHEN expiry_record.days_to_expiry < 0 
          THEN expiry_record.product_name || ' expired ' || ABS(expiry_record.days_to_expiry) || ' days ago'
          WHEN expiry_record.days_to_expiry <= 7
          THEN expiry_record.product_name || ' expires in ' || expiry_record.days_to_expiry || ' days'
          ELSE expiry_record.product_name || ' expires in ' || expiry_record.days_to_expiry || ' days'
        END,
        expiry_record.total_quantity,
        expiry_record.total_quantity * expiry_record.cost_price
      ) RETURNING id INTO alert_id;
      
      alert_count := alert_count + 1;
    END IF;
  END LOOP;
  
  RETURN alert_count;
END;
$$ LANGUAGE plpgsql;

-- Function to generate reorder suggestions
CREATE OR REPLACE FUNCTION generate_reorder_suggestions(p_tenant_id UUID)
RETURNS INTEGER AS $$
DECLARE
  suggestion_count INTEGER := 0;
  product_record RECORD;
  rule_record RECORD;
  suggestion_data RECORD;
BEGIN
  -- Process each product with reorder rules
  FOR product_record IN 
    SELECT 
      p.id,
      p.branch_id,
      p.name,
      p.stock_quantity,
      p.min_stock_level,
      p.max_stock_level,
      p.cost_price,
      p.category
    FROM public.products p
    WHERE p.tenant_id = p_tenant_id 
      AND p.is_active = TRUE
      AND p.branch_id IS NOT NULL
  LOOP
    -- Get applicable reorder rules
    FOR rule_record IN 
      SELECT * FROM public.reorder_rules rr
      WHERE rr.tenant_id = p_tenant_id
        AND (rr.branch_id IS NULL OR rr.branch_id = product_record.branch_id)
        AND (rr.product_id = product_record.id OR rr.product_category = product_record.category)
        AND rr.is_active = TRUE
    LOOP
      -- Check if reorder condition is met
      CASE rule_record.rule_type
        WHEN 'stock_level' THEN
          IF product_record.stock_quantity <= (rule_record.trigger_condition->>'min_level')::INTEGER THEN
            -- Calculate suggested quantity
            SELECT 
              CEIL(GREATEST(
                (rule_record.trigger_condition->>'target_level')::INTEGER - product_record.stock_quantity,
                (rule_record.trigger_condition->>'min_quantity')::INTEGER
              )) as suggested_qty
            INTO suggestion_data
            FROM (SELECT 1) t;
            
            -- Create suggestion
            INSERT INTO public.reorder_suggestions (
              tenant_id, branch_id, product_id, rule_id,
              suggestion_type, current_stock, suggested_quantity,
              suggested_unit_cost, total_suggested_cost, urgency_level,
              reason, confidence_score
            ) VALUES (
              p_tenant_id, product_record.branch_id, product_record.id, rule_record.id,
              'stock_level', product_record.stock_quantity, suggestion_data.suggested_qty,
              product_record.cost_price, suggestion_data.suggested_qty * product_record.cost_price,
              CASE 
                WHEN product_record.stock_quantity = 0 THEN 'critical'
                WHEN product_record.stock_quantity <= product_record.min_stock_level THEN 'high'
                ELSE 'medium'
              END,
              'Stock level below minimum threshold',
              90.0
            );
            
            suggestion_count := suggestion_count + 1;
          END IF;
          
        WHEN 'time_based' THEN
          -- Check if it's time to reorder based on schedule
          IF CURRENT_DATE >= (rule_record.trigger_condition->>'next_reorder_date')::DATE THEN
            INSERT INTO public.reorder_suggestions (
              tenant_id, branch_id, product_id, rule_id,
              suggestion_type, current_stock, suggested_quantity,
              suggested_unit_cost, total_suggested_cost, urgency_level,
              reason, confidence_score
            ) VALUES (
              p_tenant_id, product_record.branch_id, product_record.id, rule_record.id,
              'time_based', product_record.stock_quantity,
              (rule_record.trigger_condition->>'quantity')::INTEGER,
              product_record.cost_price, 
              (rule_record.trigger_condition->>'quantity')::INTEGER * product_record.cost_price,
              'medium',
              'Scheduled reorder based on time-based rule',
              85.0
            );
            
            suggestion_count := suggestion_count + 1;
          END IF;
      END CASE;
    END LOOP;
  END LOOP;
  
  RETURN suggestion_count;
END;
$$ LANGUAGE plpgsql;

-- Function to process purchase order receipt
CREATE OR REPLACE FUNCTION process_purchase_order_receipt(
  p_purchase_order_id UUID,
  p_received_by UUID,
  p_items JSONB -- Array of items with quantities received
)
RETURNS BOOLEAN AS $$
DECLARE
  po_record RECORD;
  item_record RECORD;
  batch_number TEXT;
  batch_id UUID;
  total_received INTEGER := 0;
BEGIN
  -- Get purchase order details
  SELECT * INTO po_record FROM public.purchase_orders WHERE id = p_purchase_order_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase order not found';
  END IF;
  
  -- Process each received item
  FOR item_record IN 
    SELECT * FROM jsonb_to_recordset(p_items) AS x(
      product_id UUID,
      quantity_received INTEGER,
      batch_number TEXT,
      expiry_date DATE,
      unit_cost NUMERIC
    )
  LOOP
    -- Create or update product batch
    SELECT id INTO batch_id
    FROM public.product_batches
    WHERE tenant_id = po_record.tenant_id
      AND branch_id = po_record.branch_id
      AND product_id = item_record.product_id
      AND batch_number = item_record.batch_number;
    
    IF NOT FOUND THEN
      INSERT INTO public.product_batches (
        tenant_id, branch_id, product_id, batch_number,
        supplier_id, manufacture_date, expiry_date,
        quantity_received, quantity_remaining,
        unit_cost, unit_price, received_by
      ) VALUES (
        po_record.tenant_id, po_record.branch_id, item_record.product_id,
        item_record.batch_number, po_record.supplier_id, CURRENT_DATE,
        item_record.expiry_date, item_record.quantity_received,
        item_record.quantity_received, item_record.unit_cost,
        item_record.unit_cost * 1.2, p_received_by
      ) RETURNING id INTO batch_id;
    ELSE
      UPDATE public.product_batches 
      SET quantity_received = quantity_received + item_record.quantity_received,
          quantity_remaining = quantity_remaining + item_record.quantity_received,
          unit_cost = item_record.unit_cost
      WHERE id = batch_id;
    END IF;
    
    -- Update product stock
    UPDATE public.products 
    SET stock_quantity = stock_quantity + item_record.quantity_received,
        updated_at = NOW()
    WHERE id = item_record.product_id AND branch_id = po_record.branch_id;
    
    -- Create batch transaction
    INSERT INTO public.batch_transactions (
      tenant_id, batch_id, transaction_type, quantity,
      unit_cost, total_cost, reference_id, reference_type,
      performed_by, quantity_before, quantity_after
    ) VALUES (
      po_record.tenant_id, batch_id, 'receive', item_record.quantity_received,
      item_record.unit_cost, item_record.quantity_received * item_record.unit_cost,
      p_purchase_order_id, 'purchase', p_received_by,
      0, item_record.quantity_received
    );
    
    -- Update purchase order item
    UPDATE public.purchase_order_items 
    SET quantity_received = quantity_received + item_record.quantity_received
    WHERE purchase_order_id = p_purchase_order_id
      AND product_id = item_record.product_id;
    
    total_received := total_received + item_record.quantity_received;
  END LOOP;
  
  -- Update purchase order status
  UPDATE public.purchase_orders 
  SET status = CASE 
    WHEN (SELECT SUM(quantity_ordered) FROM public.purchase_order_items WHERE purchase_order_id = p_purchase_order_id) = 
         (SELECT SUM(quantity_received) FROM public.purchase_order_items WHERE purchase_order_id = p_purchase_order_id)
    THEN 'received'
    ELSE 'partial_received'
  END,
  actual_delivery_date = CURRENT_DATE,
  received_by = p_received_by,
  received_at = NOW()
  WHERE id = p_purchase_order_id;
  
  -- Create stock movement record
  INSERT INTO public.stock_movements (
    tenant_id, branch_id, product_id, movement_type,
    quantity_change, quantity_before, quantity_after,
    reason, reference_id, reference_type, performed_by
  ) SELECT 
    po_record.tenant_id, po_record.branch_id, item_record.product_id,
    'purchase', item_record.quantity_received, 
    (SELECT stock_quantity - item_record.quantity_received FROM public.products 
     WHERE id = item_record.product_id AND branch_id = po_record.branch_id),
    (SELECT stock_quantity FROM public.products 
     WHERE id = item_record.product_id AND branch_id = po_record.branch_id),
    'Purchase order receipt', p_purchase_order_id, 'purchase', p_received_by
  FROM jsonb_to_recordset(p_items) AS x(
    product_id UUID,
    quantity_received INTEGER,
    batch_number TEXT,
    expiry_date DATE,
    unit_cost NUMERIC
  ) item_record;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 5: Advanced Inventory Views
-- ============================================================================

-- Batch Inventory View
CREATE OR REPLACE VIEW vw_batch_inventory AS
SELECT 
  pb.tenant_id,
  pb.branch_id,
  b.name as branch_name,
  pb.product_id,
  p.name as product_name,
  p.barcode,
  p.category,
  pb.batch_number,
  pb.supplier_id,
  s.name as supplier_name,
  pb.manufacture_date,
  pb.expiry_date,
  pb.quantity_received,
  pb.quantity_remaining,
  pb.quantity_sold,
  pb.quantity_wasted,
  pb.unit_cost,
  pb.unit_price,
  pb.batch_status,
  pb.quality_grade,
  (pb.quantity_remaining * pb.unit_cost) as remaining_value,
  (pb.quantity_remaining * pb.unit_price) as potential_revenue,
  CASE 
    WHEN pb.expiry_date < CURRENT_DATE THEN 'expired'
    WHEN pb.expiry_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'expiring_soon'
    WHEN pb.expiry_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'expiring_this_month'
    ELSE 'good'
  END as expiry_status,
  CURRENT_DATE - pb.manufacture_date as age_days,
  pb.expiry_date - CURRENT_DATE as days_to_expiry
FROM public.product_batches pb
LEFT JOIN public.branches b ON pb.branch_id = b.id
LEFT JOIN public.products p ON pb.product_id = p.id
LEFT JOIN public.suppliers s ON pb.supplier_id = s.id
WHERE pb.batch_status = 'active'
ORDER BY pb.expiry_date ASC;

-- Expiry Dashboard View
CREATE OR REPLACE VIEW vw_expiry_dashboard AS
SELECT 
  et.tenant_id,
  et.branch_id,
  b.name as branch_name,
  et.product_id,
  p.name as product_name,
  p.category,
  et.batch_id,
  pb.batch_number,
  et.expiry_date,
  et.days_to_expiry,
  et.expiry_status,
  et.quantity_at_risk,
  COALESCE(pb.quantity_remaining, 0) as available_quantity,
  COALESCE(pb.unit_cost, p.cost_price) as unit_cost,
  COALESCE(et.quantity_at_risk * pb.unit_cost, 0) as potential_loss,
  COUNT(ea.id) as active_alerts,
  MAX(ea.created_at) as last_alert_date
FROM public.expiry_tracking et
LEFT JOIN public.branches b ON et.branch_id = b.id
LEFT JOIN public.products p ON et.product_id = p.id
LEFT JOIN public.product_batches pb ON et.batch_id = pb.id
LEFT JOIN public.expiry_alerts ea ON et.id = ea.expiry_tracking_id AND ea.status = 'active'
WHERE et.expiry_status IN ('critical', 'warning', 'expired')
GROUP BY et.tenant_id, et.branch_id, b.name, et.product_id, p.name, p.category,
         et.batch_id, pb.batch_number, et.expiry_date, et.days_to_expiry,
         et.expiry_status, et.quantity_at_risk, pb.quantity_remaining, pb.unit_cost, p.cost_price
ORDER BY et.expiry_date ASC;

-- Reorder Suggestions View
CREATE OR REPLACE VIEW vw_reorder_suggestions AS
SELECT 
  rs.tenant_id,
  rs.branch_id,
  b.name as branch_name,
  rs.product_id,
  p.name as product_name,
  p.category,
  rs.suggestion_type,
  rs.current_stock,
  rs.suggested_quantity,
  rs.suggested_unit_cost,
  rs.total_suggested_cost,
  rs.urgency_level,
  rs.reason,
  rs.confidence_score,
  rs.status,
  rs.created_at,
  rr.rule_type,
  rr.trigger_condition
FROM public.reorder_suggestions rs
LEFT JOIN public.branches b ON rs.branch_id = b.id
LEFT JOIN public.products p ON rs.product_id = p.id
LEFT JOIN public.reorder_rules rr ON rs.rule_id = rr.id
WHERE rs.status IN ('pending', 'approved')
ORDER BY rs.urgency_level DESC, rs.confidence_score DESC;

-- Inventory Performance View
CREATE OR REPLACE VIEW vw_inventory_performance AS
SELECT 
  p.tenant_id,
  p.branch_id,
  b.name as branch_name,
  p.category,
  COUNT(*) as total_products,
  COUNT(CASE WHEN p.stock_quantity > 0 THEN 1 END) as products_with_stock,
  COUNT(CASE WHEN p.stock_quantity <= 0 THEN 1 END) as out_of_stock,
  COUNT(CASE WHEN p.stock_quantity <= p.min_stock_level THEN 1 END) as below_min_stock,
  COUNT(CASE WHEN p.stock_quantity >= p.max_stock_level THEN 1 END) as overstock,
  SUM(p.stock_quantity * p.cost_price) as total_inventory_value,
  AVG(p.stock_quantity) as avg_stock_level,
  COUNT(CASE WHEN EXISTS (
    SELECT 1 FROM public.product_batches pb 
    WHERE pb.product_id = p.id AND pb.branch_id = p.branch_id 
      AND pb.expiry_date <= CURRENT_DATE + INTERVAL '30 days'
  ) THEN 1 END) as products_expiring_soon,
  COUNT(CASE WHEN EXISTS (
    SELECT 1 FROM public.expiry_alerts ea
    JOIN public.expiry_tracking et ON ea.expiry_tracking_id = et.id
    WHERE et.product_id = p.id AND et.branch_id = p.branch_id AND ea.status = 'active'
  ) THEN 1 END) as active_expiry_alerts
FROM public.products p
LEFT JOIN public.branches b ON p.branch_id = b.id
WHERE p.is_active = TRUE
GROUP BY p.tenant_id, p.branch_id, b.name, p.category
ORDER BY total_inventory_value DESC;

-- ============================================================================
-- PART 6: Indexes for Performance
-- ============================================================================

-- Advanced inventory indexes
CREATE INDEX IF NOT EXISTS idx_product_batches_tenant_branch ON public.product_batches(tenant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_product_batches_product ON public.product_batches(product_id);
CREATE INDEX IF NOT EXISTS idx_product_batches_expiry ON public.product_batches(expiry_date);
CREATE INDEX IF NOT EXISTS idx_product_batches_status ON public.product_batches(batch_status);
CREATE INDEX IF NOT EXISTS idx_batch_transactions_batch ON public.batch_transactions(batch_id);
CREATE INDEX IF NOT EXISTS idx_expiry_tracking_expiry ON public.expiry_tracking(expiry_date);
CREATE INDEX IF NOT EXISTS idx_expiry_tracking_status ON public.expiry_tracking(expiry_status);
CREATE INDEX IF NOT EXISTS idx_expiry_alerts_status ON public.expiry_alerts(status);
CREATE INDEX IF NOT EXISTS idx_reorder_rules_tenant ON public.reorder_rules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reorder_suggestions_status ON public.reorder_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON public.purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_po ON public.purchase_order_items(purchase_order_id);

-- ============================================================================
-- PART 7: RLS Policies for Advanced Inventory Tables
-- ============================================================================

-- Enable RLS on advanced inventory tables
ALTER TABLE public.product_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.batch_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.batch_quality_control ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expiry_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expiry_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expiry_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Product Batches
CREATE POLICY "Users can view batches in their tenant" ON public.product_batches
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage batches" ON public.product_batches
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin', 'inventory_manager')
);

-- RLS Policies for Purchase Orders
CREATE POLICY "Users can view purchase orders in their tenant" ON public.purchase_orders
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage purchase orders" ON public.purchase_orders
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin', 'inventory_manager')
);

-- ============================================================================
-- PART 8: Grant Permissions
-- ============================================================================

-- Grant access to advanced inventory views
GRANT SELECT ON vw_batch_inventory TO authenticated;
GRANT SELECT ON vw_expiry_dashboard TO authenticated;
GRANT SELECT ON vw_reorder_suggestions TO authenticated;
GRANT SELECT ON vw_inventory_performance TO authenticated;

-- Grant execute permissions on advanced inventory functions
GRANT EXECUTE ON FUNCTION calculate_optimal_reorder_quantity TO authenticated;
GRANT EXECUTE ON FUNCTION check_expiry_alerts TO authenticated;
GRANT EXECUTE ON FUNCTION generate_reorder_suggestions TO authenticated;
GRANT EXECUTE ON FUNCTION process_purchase_order_receipt TO authenticated;
