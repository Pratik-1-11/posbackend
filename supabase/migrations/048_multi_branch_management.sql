-- Migration: Phase 2 - Multi-Branch Management
-- Purpose: Implement inter-branch transfers, consolidated reporting, and branch performance metrics
-- Dependencies: Requires inventory management and analytics from Phase 1 & 2

-- ============================================================================
-- PART 1: Inter-Branch Transfer System
-- ============================================================================

-- Branch Transfer Requests Table
CREATE TABLE IF NOT EXISTS public.branch_transfer_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  from_branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  to_branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  requested_by UUID NOT NULL REFERENCES public.profiles(id),
  approved_by UUID REFERENCES public.profiles(id),
  transfer_type TEXT NOT NULL CHECK (transfer_type IN ('stock', 'asset', 'document', 'cash')),
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'in_transit', 'completed', 'cancelled')),
  notes TEXT,
  rejection_reason TEXT,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  expected_delivery_date DATE,
  actual_delivery_date DATE,
  tracking_number TEXT,
  transport_method TEXT CHECK (transport_method IN ('internal', 'courier', 'pickup', 'other')),
  estimated_cost NUMERIC(10, 2),
  actual_cost NUMERIC(10, 2),
  CHECK (from_branch_id != to_branch_id)
);

-- Branch Transfer Items Table
CREATE TABLE IF NOT EXISTS public.branch_transfer_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  transfer_request_id UUID NOT NULL REFERENCES public.branch_transfer_requests(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id),
  batch_number TEXT, -- For batch tracking
  quantity_requested INTEGER NOT NULL CHECK (quantity_requested > 0),
  quantity_approved INTEGER DEFAULT 0 CHECK (quantity_approved >= 0),
  quantity_sent INTEGER DEFAULT 0 CHECK (quantity_sent >= 0),
  quantity_received INTEGER DEFAULT 0 CHECK (quantity_received >= 0),
  unit_cost NUMERIC(10, 2),
  condition_at_transfer TEXT CHECK (condition_at_transfer IN ('new', 'good', 'used', 'damaged')),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Branch Transfer History Table
CREATE TABLE IF NOT EXISTS public.branch_transfer_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  transfer_request_id UUID NOT NULL REFERENCES public.branch_transfer_requests(id) ON DELETE CASCADE,
  from_branch_id UUID NOT NULL REFERENCES public.branches(id),
  to_branch_id UUID NOT NULL REFERENCES public.branches(id),
  product_id UUID NOT NULL REFERENCES public.products(id),
  quantity INTEGER NOT NULL,
  transfer_date TIMESTAMPTZ DEFAULT NOW(),
  transferred_by UUID NOT NULL REFERENCES public.profiles(id),
  received_by UUID REFERENCES public.profiles(id),
  batch_number TEXT,
  unit_cost NUMERIC(10, 2),
  total_cost NUMERIC(12, 2),
  condition_at_transfer TEXT,
  condition_at_receipt TEXT,
  notes TEXT,
  received_at TIMESTAMPTZ
);

-- ============================================================================
-- PART 2: Branch Performance Metrics
-- ============================================================================

-- Branch Performance KPIs Table
CREATE TABLE IF NOT EXISTS public.branch_performance_kpis (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  kpi_date DATE NOT NULL,
  period_type TEXT NOT NULL CHECK (period_type IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')),
  
  -- Sales Metrics
  total_sales NUMERIC(12, 2) DEFAULT 0,
  net_sales NUMERIC(12, 2) DEFAULT 0,
  gross_profit NUMERIC(12, 2) DEFAULT 0,
  net_profit NUMERIC(12, 2) DEFAULT 0,
  profit_margin_percent NUMERIC(5, 2) DEFAULT 0,
  total_transactions INTEGER DEFAULT 0,
  avg_transaction_value NUMERIC(10, 2) DEFAULT 0,
  unique_customers INTEGER DEFAULT 0,
  customer_retention_rate NUMERIC(5, 2) DEFAULT 0,
  
  -- Inventory Metrics
  inventory_turnover_ratio NUMERIC(8, 2) DEFAULT 0,
  stock_out_count INTEGER DEFAULT 0,
  overstock_value NUMERIC(12, 2) DEFAULT 0,
  dead_stock_value NUMERIC(12, 2) DEFAULT 0,
  inventory_accuracy_percent NUMERIC(5, 2) DEFAULT 0,
  
  -- Operational Metrics
  staff_productivity NUMERIC(8, 2) DEFAULT 0, -- Sales per staff member
  labor_cost_percent NUMERIC(5, 2) DEFAULT 0,
  operating_expenses NUMERIC(12, 2) DEFAULT 0,
  utility_costs NUMERIC(10, 2) DEFAULT 0,
  maintenance_costs NUMERIC(10, 2) DEFAULT 0,
  
  -- Customer Service Metrics
  customer_satisfaction_score NUMERIC(3, 2) DEFAULT 0, -- 1-5 scale
  complaint_resolution_time_hours NUMERIC(8, 2) DEFAULT 0,
  positive_feedback_count INTEGER DEFAULT 0,
  negative_feedback_count INTEGER DEFAULT 0,
  
  -- Performance Scores
  overall_score NUMERIC(5, 2) DEFAULT 0, -- 0-100 scale
  sales_performance_score NUMERIC(5, 2) DEFAULT 0,
  inventory_performance_score NUMERIC(5, 2) DEFAULT 0,
  operational_performance_score NUMERIC(5, 2) DEFAULT 0,
  customer_service_score NUMERIC(5, 2) DEFAULT 0,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, branch_id, kpi_date, period_type)
);

-- Branch Targets Table
CREATE TABLE IF NOT EXISTS public.branch_targets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE, -- NULL for tenant-wide targets
  target_type TEXT NOT NULL CHECK (target_type IN ('sales', 'profit', 'transactions', 'customers', 'inventory', 'customer_service')),
  target_period TEXT NOT NULL CHECK (target_period IN ('daily', 'weekly', 'monthly', 'quarterly', 'yearly')),
  target_value NUMERIC(12, 2) NOT NULL,
  target_unit TEXT CHECK (target_unit IN ('currency', 'count', 'percentage', 'ratio')),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Branch Target Achievements Table
CREATE TABLE IF NOT EXISTS public.branch_target_achievements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES public.branch_targets(id) ON DELETE CASCADE,
  achievement_date DATE NOT NULL,
  actual_value NUMERIC(12, 2) NOT NULL,
  target_value NUMERIC(12, 2) NOT NULL,
  achievement_percent NUMERIC(5, 2) GENERATED ALWAYS AS (
    CASE 
      WHEN target_value > 0 THEN ROUND((actual_value / target_value) * 100, 2)
      ELSE 0
    END
  ) STORED,
  is_achieved BOOLEAN GENERATED ALWAYS AS (actual_value >= target_value) STORED,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(branch_id, target_id, achievement_date)
);

-- ============================================================================
-- PART 3: Consolidated Reporting
-- ============================================================================

-- Consolidated Daily Sales View
CREATE OR REPLACE VIEW vw_consolidated_daily_sales AS
SELECT 
  DATE_TRUNC('day', s.created_at) as sale_date,
  s.tenant_id,
  t.name as tenant_name,
  COUNT(*) as total_transactions,
  SUM(s.total_amount) as gross_sales,
  SUM(s.discount_amount) as total_discount,
  SUM(s.tax_amount) as total_tax,
  SUM(s.net_amount) as net_sales,
  AVG(s.total_amount) as avg_transaction_value,
  COUNT(DISTINCT s.customer_id) as unique_customers,
  COUNT(DISTINCT s.branch_id) as active_branches,
  COUNT(CASE WHEN s.branch_id IS NOT NULL THEN 1 END) as branch_transactions,
  COUNT(CASE WHEN s.branch_id IS NULL THEN 1 END) as online_transactions,
  SUM(CASE WHEN s.branch_id IS NOT NULL THEN s.net_amount ELSE 0 END) as branch_sales,
  SUM(CASE WHEN s.branch_id IS NULL THEN s.net_amount ELSE 0 END) as online_sales
FROM public.sales s
LEFT JOIN public.tenants t ON s.tenant_id = t.id
WHERE s.status = 'completed'
GROUP BY DATE_TRUNC('day', s.created_at), s.tenant_id, t.name
ORDER BY sale_date DESC;

-- Consolidated Branch Performance View
CREATE OR REPLACE VIEW vw_consolidated_branch_performance AS
WITH branch_daily_metrics AS (
  SELECT 
    DATE_TRUNC('day', s.created_at) as performance_date,
    s.tenant_id,
    s.branch_id,
    b.name as branch_name,
    b.location,
    b.branch_type,
    COUNT(*) as daily_transactions,
    SUM(s.net_amount) as daily_sales,
    AVG(s.total_amount) as avg_transaction_value,
    COUNT(DISTINCT s.customer_id) as unique_customers_daily,
    COUNT(DISTINCT si.product_id) as products_sold_daily,
    SUM(si.quantity) as total_items_sold_daily
  FROM public.sales s
  LEFT JOIN public.branches b ON s.branch_id = b.id
  LEFT JOIN public.sale_items si ON s.id = si.sale_id
  WHERE s.status = 'completed'
  GROUP BY DATE_TRUNC('day', s.created_at), s.tenant_id, s.branch_id, b.name, b.location, b.branch_type
)
SELECT 
  bdm.tenant_id,
  bdm.branch_id,
  bdm.branch_name,
  bdm.location,
  bdm.branch_type,
  bdm.performance_date,
  bdm.daily_transactions,
  bdm.daily_sales,
  bdm.avg_transaction_value,
  bdm.unique_customers_daily,
  bdm.products_sold_daily,
  bdm.total_items_sold_daily,
  -- Rolling averages
  AVG(bdm.daily_sales) OVER (PARTITION BY bdm.branch_id ORDER BY bdm.performance_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_7day_sales,
  AVG(bdm.daily_transactions) OVER (PARTITION BY bdm.branch_id ORDER BY bdm.performance_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as rolling_7day_transactions,
  -- Month-to-date calculations
  SUM(bdm.daily_sales) OVER (PARTITION BY bdm.branch_id, DATE_TRUNC('month', bdm.performance_date) ORDER BY bdm.performance_date) as mtd_sales,
  SUM(bdm.daily_transactions) OVER (PARTITION BY bdm.branch_id, DATE_TRUNC('month', bdm.performance_date) ORDER BY bdm.performance_date) as mtd_transactions,
  -- Year-to-date calculations
  SUM(bdm.daily_sales) OVER (PARTITION BY bdm.branch_id, DATE_TRUNC('year', bdm.performance_date) ORDER BY bdm.performance_date) as ytd_sales,
  SUM(bdm.daily_transactions) OVER (PARTITION BY bdm.branch_id, DATE_TRUNC('year', bdm.performance_date) ORDER BY bdm.performance_date) as ytd_transactions
FROM branch_daily_metrics bdm
ORDER BY bdm.performance_date DESC;

-- Inter-Branch Transfer Summary View
CREATE OR REPLACE VIEW vw_interbranch_transfer_summary AS
SELECT 
  btr.tenant_id,
  DATE_TRUNC('month', btr.requested_at) as transfer_month,
  fb.name as from_branch_name,
  tb.name as to_branch_name,
  btr.transfer_type,
  COUNT(*) as total_transfers,
  COUNT(CASE WHEN btr.status = 'completed' THEN 1 END) as completed_transfers,
  COUNT(CASE WHEN btr.status = 'pending' THEN 1 END) as pending_transfers,
  COUNT(CASE WHEN btr.status = 'in_transit' THEN 1 END) as in_transit_transfers,
  SUM(COALESCE(bti.quantity_sent, 0)) as total_quantity_sent,
  SUM(COALESCE(bti.quantity_received, 0)) as total_quantity_received,
  SUM(COALESCE(btr.actual_cost, 0)) as total_transfer_cost,
  AVG(COALESCE(btr.actual_cost, 0)) as avg_transfer_cost,
  AVG(EXTRACT(EPOCH FROM (btr.completed_at - btr.requested_at))/3600) as avg_completion_hours
FROM public.branch_transfer_requests btr
LEFT JOIN public.branches fb ON btr.from_branch_id = fb.id
LEFT JOIN public.branches tb ON btr.to_branch_id = tb.id
LEFT JOIN public.branch_transfer_items bti ON btr.id = bti.transfer_request_id
GROUP BY btr.tenant_id, DATE_TRUNC('month', btr.requested_at), fb.name, tb.name, btr.transfer_type
ORDER BY transfer_month DESC;

-- Branch Inventory Consolidation View
CREATE OR REPLACE VIEW vw_branch_inventory_consolidation AS
SELECT 
  p.tenant_id,
  DATE_TRUNC('day', CURRENT_TIMESTAMP) as inventory_date,
  COUNT(DISTINCT p.branch_id) as total_branches,
  COUNT(*) as total_products_across_branches,
  SUM(p.stock_quantity) as total_inventory_units,
  SUM(p.stock_quantity * p.cost_price) as total_inventory_value,
  SUM(p.stock_quantity * p.selling_price) as total_retail_value,
  AVG(p.stock_quantity) as avg_stock_per_product,
  COUNT(CASE WHEN p.stock_quantity <= 0 THEN 1 END) as total_out_of_stock_items,
  COUNT(CASE WHEN p.stock_quantity <= p.min_stock_level THEN 1 END) as total_low_stock_items,
  COUNT(CASE WHEN p.stock_quantity >= p.max_stock_level THEN 1 END) as total_overstock_items,
  -- Branch-specific metrics
  COUNT(DISTINCT CASE WHEN p.stock_quantity > 0 THEN p.branch_id END) as branches_with_stock,
  COUNT(DISTINCT CASE WHEN p.stock_quantity <= p.min_stock_level THEN p.branch_id END) as branches_with_low_stock,
  -- Category breakdown
  COUNT(DISTINCT p.category) as total_categories,
  STRING_AGG(DISTINCT p.category, ', ') as categories_list
FROM public.products p
WHERE p.is_active = TRUE
GROUP BY p.tenant_id;

-- ============================================================================
-- PART 4: Multi-Branch Functions
-- ============================================================================

-- Function to calculate branch performance KPIs
CREATE OR REPLACE FUNCTION calculate_branch_kpis(
  p_tenant_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_kpi_date DATE DEFAULT CURRENT_DATE,
  p_period TEXT DEFAULT 'daily'
)
RETURNS VOID AS $$
DECLARE
  branch_record RECORD;
  sales_metrics RECORD;
  inventory_metrics RECORD;
  operational_metrics RECORD;
  customer_service_metrics RECORD;
  overall_score NUMERIC;
BEGIN
  -- Process each branch if branch_id is NULL
  FOR branch_record IN 
    SELECT id, name 
    FROM public.branches 
    WHERE tenant_id = p_tenant_id 
      AND (p_branch_id IS NULL OR id = p_branch_id)
      AND is_active = TRUE
  LOOP
    -- Calculate sales metrics
    SELECT 
      COALESCE(SUM(s.net_amount), 0) as net_sales,
      COALESCE(SUM(s.total_amount), 0) as gross_sales,
      COALESCE(SUM(s.total_amount - s.cost_amount), 0) as gross_profit,
      COUNT(*) as total_transactions,
      COALESCE(AVG(s.total_amount), 0) as avg_transaction_value,
      COUNT(DISTINCT s.customer_id) as unique_customers
    INTO sales_metrics
    FROM public.sales s
    WHERE s.tenant_id = p_tenant_id 
      AND s.branch_id = branch_record.id
      AND s.status = 'completed'
      AND CASE 
        WHEN p_period = 'daily' THEN DATE(s.created_at) = p_kpi_date
        WHEN p_period = 'weekly' THEN DATE_TRUNC('week', s.created_at)::DATE = p_kpi_date
        WHEN p_period = 'monthly' THEN DATE_TRUNC('month', s.created_at)::DATE = p_kpi_date
      END;
    
    -- Calculate inventory metrics
    SELECT 
      COUNT(CASE WHEN p.stock_quantity <= 0 THEN 1 END) as stock_out_count,
      SUM(CASE WHEN p.stock_quantity >= p.max_stock_level THEN p.stock_quantity * p.cost_price ELSE 0 END) as overstock_value,
      COUNT(*) as total_products,
      SUM(p.stock_quantity) as total_stock
    INTO inventory_metrics
    FROM public.products p
    WHERE p.tenant_id = p_tenant_id AND p.branch_id = branch_record.id AND p.is_active = TRUE;
    
    -- Calculate customer service metrics
    SELECT 
      COALESCE(AVG(cf.rating), 0) as avg_satisfaction,
      COUNT(CASE WHEN cf.rating >= 4 THEN 1 END) as positive_count,
      COUNT(CASE WHEN cf.rating <= 2 THEN 1 END) as negative_count,
      COALESCE(AVG(EXTRACT(EPOCH FROM (cf.resolved_at - cf.created_at))/3600), 0) as avg_resolution_hours
    INTO customer_service_metrics
    FROM public.customer_feedback cf
    WHERE cf.tenant_id = p_tenant_id 
      AND cf.branch_id = branch_record.id
      AND cf.created_at >= p_kpi_date - INTERVAL CASE 
        WHEN p_period = 'daily' THEN '1 day'
        WHEN p_period = 'weekly' THEN '7 days'
        WHEN p_period = 'monthly' THEN '30 days'
      END;
    
    -- Calculate performance scores
    overall_score := (
      CASE 
        WHEN sales_metrics.net_sales > 0 THEN 
          LEAST((sales_metrics.net_sales / 10000) * 20, 20) -- Sales score (max 20)
        ELSE 0
      END +
      CASE 
        WHEN inventory_metrics.total_products > 0 THEN 
          LEAST(((inventory_metrics.total_products - inventory_metrics.stock_out_count) * 20.0 / inventory_metrics.total_products), 20) -- Inventory score (max 20)
        ELSE 0
      END +
      CASE 
        WHEN customer_service_metrics.avg_satisfaction > 0 THEN 
          (customer_service_metrics.avg_satisfaction * 4) -- Service score (max 20)
        ELSE 0
      END +
      40 -- Base score
    );
    
    -- Insert or update KPIs
    INSERT INTO public.branch_performance_kpis (
      tenant_id, branch_id, kpi_date, period_type,
      total_sales, net_sales, gross_profit, total_transactions,
      avg_transaction_value, unique_customers, stock_out_count,
      overstock_value, customer_satisfaction_score,
      positive_feedback_count, negative_feedback_count,
      complaint_resolution_time_hours, overall_score
    ) VALUES (
      p_tenant_id, branch_record.id, p_kpi_date, p_period,
      sales_metrics.gross_sales, sales_metrics.net_sales, sales_metrics.gross_profit,
      sales_metrics.total_transactions, sales_metrics.avg_transaction_value,
      sales_metrics.unique_customers, inventory_metrics.stock_out_count,
      inventory_metrics.overstock_value, customer_service_metrics.avg_satisfaction,
      customer_service_metrics.positive_count, customer_service_metrics.negative_count,
      customer_service_metrics.avg_resolution_hours, overall_score
    )
    ON CONFLICT (tenant_id, branch_id, kpi_date, period_type)
    DO UPDATE SET
      total_sales = EXCLUDED.total_sales,
      net_sales = EXCLUDED.net_sales,
      gross_profit = EXCLUDED.gross_profit,
      total_transactions = EXCLUDED.total_transactions,
      avg_transaction_value = EXCLUDED.avg_transaction_value,
      unique_customers = EXCLUDED.unique_customers,
      stock_out_count = EXCLUDED.stock_out_count,
      overstock_value = EXCLUDED.overstock_value,
      customer_satisfaction_score = EXCLUDED.customer_satisfaction_score,
      positive_feedback_count = EXCLUDED.positive_feedback_count,
      negative_feedback_count = EXCLUDED.negative_feedback_count,
      complaint_resolution_time_hours = EXCLUDED.complaint_resolution_time_hours,
      overall_score = EXCLUDED.overall_score,
      updated_at = NOW();
  END LOOP;
  
  RAISE NOTICE 'Branch KPIs calculated for tenant %', p_tenant_id;
END;
$$ LANGUAGE plpgsql;

-- Function to process inter-branch transfer
CREATE OR REPLACE FUNCTION process_branch_transfer(
  p_transfer_request_id UUID,
  p_processed_by UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  transfer_record RECORD;
  item_record RECORD;
  from_product RECORD;
  to_product RECORD;
  transfer_success BOOLEAN := TRUE;
BEGIN
  -- Get transfer request details
  SELECT tr.*, fb.name as from_branch_name, tb.name as to_branch_name
  INTO transfer_record
  FROM public.branch_transfer_requests tr
  LEFT JOIN public.branches fb ON tr.from_branch_id = fb.id
  LEFT JOIN public.branches tb ON tr.to_branch_id = tb.id
  WHERE tr.id = p_transfer_request_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer request not found';
  END IF;
  
  IF transfer_record.status != 'approved' THEN
    RAISE EXCEPTION 'Transfer request must be approved before processing';
  END IF;
  
  -- Process each transfer item
  FOR item_record IN 
    SELECT * FROM public.branch_transfer_items 
    WHERE transfer_request_id = p_transfer_request_id
  LOOP
    -- Check source branch stock
    SELECT stock_quantity, cost_price, selling_price
    INTO from_product
    FROM public.products
    WHERE id = item_record.product_id 
      AND branch_id = transfer_record.from_branch_id;
    
    IF NOT FOUND OR from_product.stock_quantity < item_record.quantity_sent THEN
      transfer_success := FALSE;
      RAISE NOTICE 'Insufficient stock for product % in branch %', item_record.product_id, transfer_record.from_branch_name;
    ELSE
      -- Reduce stock from source branch
      UPDATE public.products 
      SET stock_quantity = stock_quantity - item_record.quantity_sent
      WHERE id = item_record.product_id 
        AND branch_id = transfer_record.from_branch_id;
      
      -- Check if product exists in destination branch
      SELECT stock_quantity
      INTO to_product
      FROM public.products
      WHERE id = item_record.product_id 
        AND branch_id = transfer_record.to_branch_id;
      
      IF FOUND THEN
        -- Add stock to destination branch
        UPDATE public.products 
        SET stock_quantity = stock_quantity + item_record.quantity_sent
        WHERE id = item_record.product_id 
          AND branch_id = transfer_record.to_branch_id;
      ELSE
        -- Create product record in destination branch
        INSERT INTO public.products (
          tenant_id, branch_id, name, barcode, category, brand,
          cost_price, selling_price, stock_quantity, min_stock_level,
          max_stock_level, is_active, created_at, updated_at
        )
        SELECT 
          tenant_id, transfer_record.to_branch_id, name, barcode, category, brand,
          cost_price, selling_price, item_record.quantity_sent, min_stock_level,
          max_stock_level, TRUE, NOW(), NOW()
        FROM public.products
        WHERE id = item_record.product_id 
          AND branch_id = transfer_record.from_branch_id;
      END IF;
      
      -- Create transfer history record
      INSERT INTO public.branch_transfer_history (
        tenant_id, transfer_request_id, from_branch_id, to_branch_id,
        product_id, quantity, transferred_by, unit_cost,
        total_cost, condition_at_transfer, notes
      ) VALUES (
        transfer_record.tenant_id, p_transfer_request_id,
        transfer_record.from_branch_id, transfer_record.to_branch_id,
        item_record.product_id, item_record.quantity_sent, p_processed_by,
        from_product.cost_price, item_record.quantity_sent * from_product.cost_price,
        item_record.condition_at_transfer, item_record.notes
      );
      
      -- Create stock movement records
      INSERT INTO public.stock_movements (
        tenant_id, branch_id, product_id, movement_type,
        quantity_change, quantity_before, quantity_after,
        reason, reference_id, reference_type, performed_by
      ) VALUES 
        -- Source branch movement
        (transfer_record.tenant_id, transfer_record.from_branch_id, item_record.product_id,
         'transfer_out', -item_record.quantity_sent, from_product.stock_quantity,
         from_product.stock_quantity - item_record.quantity_sent,
         'Inter-branch transfer to ' || transfer_record.to_branch_name,
         p_transfer_request_id, 'transfer', p_processed_by),
        -- Destination branch movement
        (transfer_record.tenant_id, transfer_record.to_branch_id, item_record.product_id,
         'transfer_in', item_record.quantity_sent, COALESCE(to_product.stock_quantity, 0),
         COALESCE(to_product.stock_quantity, 0) + item_record.quantity_sent,
         'Inter-branch transfer from ' || transfer_record.from_branch_name,
         p_transfer_request_id, 'transfer', p_processed_by);
    END IF;
  END LOOP;
  
  -- Update transfer request status
  UPDATE public.branch_transfer_requests 
  SET status = CASE WHEN transfer_success THEN 'completed' ELSE 'failed' END,
      completed_at = NOW()
  WHERE id = p_transfer_request_id;
  
  RETURN transfer_success;
END;
$$ LANGUAGE plpgsql;

-- Function to generate consolidated report
CREATE OR REPLACE FUNCTION generate_consolidated_report(
  p_tenant_id UUID,
  p_report_type TEXT DEFAULT 'sales',
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL,
  p_branch_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
  report_date DATE,
  metric_name TEXT,
  metric_value NUMERIC,
  branch_name TEXT,
  comparison_value NUMERIC,
  variance_percent NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH date_range AS (
    SELECT 
      COALESCE(p_start_date, CURRENT_DATE - INTERVAL '30 days') as start_date,
      COALESCE(p_end_date, CURRENT_DATE) as end_date
  ),
  filtered_branches AS (
    SELECT id, name 
    FROM public.branches 
    WHERE tenant_id = p_tenant_id 
      AND is_active = TRUE
      AND (p_branch_ids IS NULL OR id = ANY(p_branch_ids))
  )
  SELECT 
    dr.start_date as report_date,
    'Total Sales' as metric_name,
    COALESCE(SUM(s.net_amount), 0) as metric_value,
    'All Branches' as branch_name,
    LAG(COALESCE(SUM(s.net_amount), 0), 1) OVER (ORDER BY dr.start_date) as comparison_value,
    CASE 
      WHEN LAG(COALESCE(SUM(s.net_amount), 0), 1) OVER (ORDER BY dr.start_date) > 0
      THEN ROUND(((COALESCE(SUM(s.net_amount), 0) - LAG(COALESCE(SUM(s.net_amount), 0), 1) OVER (ORDER BY dr.start_date)) / 
                  LAG(COALESCE(SUM(s.net_amount), 0), 1) OVER (ORDER BY dr.start_date)) * 100, 2)
      ELSE NULL
    END as variance_percent
  FROM date_range dr, filtered_branches fb
  LEFT JOIN public.sales s ON fb.id = s.branch_id 
    AND s.tenant_id = p_tenant_id 
    AND DATE(s.created_at) BETWEEN dr.start_date AND dr.end_date
    AND s.status = 'completed'
  GROUP BY dr.start_date
  
  UNION ALL
  
  SELECT 
    dr.start_date,
    'Total Transactions' as metric_name,
    COALESCE(COUNT(s.id), 0) as metric_value,
    'All Branches' as branch_name,
    LAG(COALESCE(COUNT(s.id), 0), 1) OVER (ORDER BY dr.start_date) as comparison_value,
    CASE 
      WHEN LAG(COALESCE(COUNT(s.id), 0), 1) OVER (ORDER BY dr.start_date) > 0
      THEN ROUND(((COALESCE(COUNT(s.id), 0) - LAG(COALESCE(COUNT(s.id), 0), 1) OVER (ORDER BY dr.start_date)) / 
                  LAG(COALESCE(COUNT(s.id), 0), 1) OVER (ORDER BY dr.start_date)) * 100, 2)
      ELSE NULL
    END as variance_percent
  FROM date_range dr, filtered_branches fb
  LEFT JOIN public.sales s ON fb.id = s.branch_id 
    AND s.tenant_id = p_tenant_id 
    AND DATE(s.created_at) BETWEEN dr.start_date AND dr.end_date
    AND s.status = 'completed'
  GROUP BY dr.start_date;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 5: Indexes for Performance
-- ============================================================================

-- Multi-Branch indexes
CREATE INDEX IF NOT EXISTS idx_branch_transfer_requests_tenant ON public.branch_transfer_requests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_branch_transfer_requests_branches ON public.branch_transfer_requests(from_branch_id, to_branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_transfer_requests_status ON public.branch_transfer_requests(status);
CREATE INDEX IF NOT EXISTS idx_branch_transfer_items_request ON public.branch_transfer_items(transfer_request_id);
CREATE INDEX IF NOT EXISTS idx_branch_transfer_history_tenant ON public.branch_transfer_history(tenant_id);
CREATE INDEX IF NOT EXISTS idx_branch_performance_kpis_tenant_branch ON public.branch_performance_kpis(tenant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_branch_targets_tenant ON public.branch_targets(tenant_id);
CREATE INDEX IF NOT EXISTS idx_branch_target_achievements_branch_target ON public.branch_target_achievements(branch_id, target_id);

-- ============================================================================
-- PART 6: RLS Policies for Multi-Branch Tables
-- ============================================================================

-- Enable RLS on multi-branch tables
ALTER TABLE public.branch_transfer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_transfer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_transfer_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_performance_kpis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_target_achievements ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Transfer Requests
CREATE POLICY "Users can view transfers in their tenant" ON public.branch_transfer_requests
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage transfers" ON public.branch_transfer_requests
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- RLS Policies for Performance KPIs
CREATE POLICY "Users can view KPIs in their tenant" ON public.branch_performance_kpis
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage KPIs" ON public.branch_performance_kpis
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- ============================================================================
-- PART 7: Grant Permissions
-- ============================================================================

-- Grant access to multi-branch views
GRANT SELECT ON vw_consolidated_daily_sales TO authenticated;
GRANT SELECT ON vw_consolidated_branch_performance TO authenticated;
GRANT SELECT ON vw_interbranch_transfer_summary TO authenticated;
GRANT SELECT ON vw_branch_inventory_consolidation TO authenticated;

-- Grant execute permissions on multi-branch functions
GRANT EXECUTE ON FUNCTION calculate_branch_kpis TO authenticated;
GRANT EXECUTE ON FUNCTION process_branch_transfer TO authenticated;
GRANT EXECUTE ON FUNCTION generate_consolidated_report TO authenticated;
