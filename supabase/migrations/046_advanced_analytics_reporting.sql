-- Migration: Phase 2 - Advanced Analytics & Reporting Dashboard
-- Purpose: Create comprehensive analytics views and stored procedures for business intelligence
-- Dependencies: Requires all Phase 1 tables and data to be established

-- ============================================================================
-- PRE-REQUISITES: Ensure branch_id exists in sales table
-- ============================================================================

DO $$
BEGIN
    -- Add branch_id to sales table if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'sales' 
        AND table_schema = 'public' 
        AND column_name = 'branch_id'
    ) THEN
        ALTER TABLE public.sales ADD COLUMN branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added branch_id to sales table';
    END IF;
END $$;

-- ============================================================================
-- PART 1: Analytics Summary Views
-- ============================================================================

-- Daily Sales Summary View
CREATE OR REPLACE VIEW vw_daily_sales_summary AS
SELECT 
  DATE_TRUNC('day', s.created_at) as sale_date,
  b.tenant_id,
  s.branch_id,
  b.name as branch_name,
  COUNT(*) as total_transactions,
  SUM(s.total_amount) as gross_sales,
  SUM(s.discount_amount) as total_discount,
  SUM(s.vat_amount) as total_tax,
  SUM(s.sub_total) as net_sales,
  AVG(s.total_amount) as avg_transaction_value,
  COUNT(DISTINCT CASE WHEN s.customer_name != 'Walk-in' THEN s.customer_name END) as unique_customers,
  COUNT(CASE WHEN s.customer_name != 'Walk-in' THEN 1 END) as customer_transactions,
  COUNT(CASE WHEN s.payment_method = 'cash' THEN 1 END) as cash_transactions,
  COUNT(CASE WHEN s.payment_method = 'card' THEN 1 END) as card_transactions,
  COUNT(CASE WHEN s.payment_method = 'qr' THEN 1 END) as qr_transactions,
  COUNT(CASE WHEN s.payment_method = 'mixed' THEN 1 END) as mixed_transactions
FROM public.sales s
LEFT JOIN public.branches b ON s.branch_id = b.id
WHERE s.status = 'completed'
GROUP BY DATE_TRUNC('day', s.created_at), b.tenant_id, s.branch_id, b.name
ORDER BY sale_date DESC;

-- Monthly Sales Performance View
CREATE OR REPLACE VIEW vw_monthly_sales_performance AS
SELECT 
  DATE_TRUNC('month', s.created_at) as month,
  b.tenant_id,
  s.branch_id,
  b.name as branch_name,
  COUNT(*) as total_transactions,
  SUM(s.total_amount) as gross_sales,
  SUM(s.discount_amount) as total_discount,
  SUM(s.vat_amount) as total_tax,
  SUM(s.sub_total) as net_sales,
  AVG(s.total_amount) as avg_transaction_value,
  COUNT(DISTINCT CASE WHEN s.customer_name != 'Walk-in' THEN s.customer_name END) as unique_customers,
  SUM(s.total_amount) / COUNT(DISTINCT DATE_TRUNC('day', s.created_at)) as daily_average,
  LAG(SUM(s.sub_total), 1) OVER (PARTITION BY b.tenant_id, s.branch_id ORDER BY DATE_TRUNC('month', s.created_at)) as previous_month_sales,
  CASE 
    WHEN LAG(SUM(s.sub_total), 1) OVER (PARTITION BY b.tenant_id, s.branch_id ORDER BY DATE_TRUNC('month', s.created_at)) > 0
    THEN ROUND(((SUM(s.sub_total) - LAG(SUM(s.sub_total), 1) OVER (PARTITION BY b.tenant_id, s.branch_id ORDER BY DATE_TRUNC('month', s.created_at))) / 
                LAG(SUM(s.sub_total), 1) OVER (PARTITION BY b.tenant_id, s.branch_id ORDER BY DATE_TRUNC('month', s.created_at))) * 100, 2)
    ELSE NULL
  END as month_over_month_growth
FROM public.sales s
LEFT JOIN public.branches b ON s.branch_id = b.id
WHERE s.status = 'completed'
GROUP BY DATE_TRUNC('month', s.created_at), b.tenant_id, s.branch_id, b.name
ORDER BY month DESC;

-- Product Performance Analytics View
CREATE OR REPLACE VIEW vw_product_performance AS
SELECT 
  p.id as product_id,
  p.name as product_name,
  p.barcode,
  COALESCE(c.name, 'Uncategorized') as category,
  COALESCE(si.total_sold, 0) as total_units_sold,
  COALESCE(si.total_revenue, 0) as total_revenue,
  COALESCE(si.total_cost, 0) as total_cost,
  COALESCE(total_profit, 0) as gross_profit,
  CASE 
    WHEN COALESCE(si.total_cost, 0) > 0 
    THEN ROUND(((COALESCE(si.total_revenue, 0) - COALESCE(si.total_cost, 0)) / COALESCE(si.total_cost, 0)) * 100, 2)
    ELSE NULL
  END as profit_margin_percent,
  p.stock_quantity,
  p.min_stock_level,
  CASE 
    WHEN p.stock_quantity <= p.min_stock_level THEN 'Critical'
    WHEN p.stock_quantity <= (p.min_stock_level * 2) THEN 'Low'
    ELSE 'Normal'
  END as stock_status,
  p.is_active,
  si.times_sold,
  AVG(si.avg_unit_price) as avg_selling_price,
  CASE WHEN si.has_recent_sales = TRUE THEN 1 ELSE 0 END as sold_last_30_days,
  si.units_sold_last_30_days
FROM public.products p
LEFT JOIN public.categories c ON p.category_id = c.id
LEFT JOIN (
  SELECT 
    si.product_id,
    SUM(si.quantity) as total_sold,
    SUM(si.total_price) as total_revenue,
    SUM(si.quantity * p.cost_price) as total_cost,
    AVG(si.unit_price) as avg_unit_price,
    SUM(si.total_price - (si.quantity * p.cost_price)) as total_profit,
    COUNT(DISTINCT si.sale_id) as times_sold,
    COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as recent_sales_count,
    CASE WHEN COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) > 0 THEN TRUE ELSE FALSE END as has_recent_sales,
    COALESCE(SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN si.quantity END), 0) as units_sold_last_30_days
  FROM public.sale_items si
  LEFT JOIN public.products p ON si.product_id = p.id
  LEFT JOIN public.sales s ON si.sale_id = s.id
  WHERE s.status = 'completed'
  GROUP BY si.product_id
) si ON p.id = si.product_id
GROUP BY p.id, p.name, p.barcode, c.name, p.stock_quantity, p.min_stock_level, p.is_active, si.total_sold, si.total_revenue, si.total_cost, total_profit, si.times_sold, si.has_recent_sales, si.units_sold_last_30_days
ORDER BY total_revenue DESC;

-- Customer Analytics View
CREATE OR REPLACE VIEW vw_customer_analytics AS
SELECT 
  c.tenant_id,
  c.id as customer_id,
  c.name as customer_name,
  c.phone,
  c.email,
  COUNT(DISTINCT s.id) as total_orders,
  COALESCE(SUM(s.sub_total), 0) as total_spent,
  AVG(s.sub_total) as avg_order_value,
  MAX(s.created_at) as last_purchase_date,
  MIN(s.created_at) as first_purchase_date,
  CURRENT_DATE - MAX(s.created_at) as days_since_last_purchase,
  COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as orders_last_30_days,
  COALESCE(SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN s.sub_total END), 0) as spent_last_30_days,
  COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN 1 END) as orders_last_90_days,
  COALESCE(SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '90 days' THEN s.sub_total END), 0) as spent_last_90_days,
  -- Fixed: Using AGE function for proper interval to integer comparison
  CASE 
    WHEN EXTRACT(DAYS FROM AGE(CURRENT_DATE, MAX(s.created_at))) <= 30 THEN 'Active'
    WHEN EXTRACT(DAYS FROM AGE(CURRENT_DATE, MAX(s.created_at))) <= 90 THEN 'At Risk'
    WHEN EXTRACT(DAYS FROM AGE(CURRENT_DATE, MAX(s.created_at))) <= 180 THEN 'Dormant'
    ELSE 'Inactive'
  END as customer_status,
  CASE 
    WHEN COALESCE(SUM(s.sub_total), 0) >= 50000 THEN 'VIP'
    WHEN COALESCE(SUM(s.sub_total), 0) >= 20000 THEN 'Premium'
    WHEN COALESCE(SUM(s.sub_total), 0) >= 5000 THEN 'Regular'
    ELSE 'Occasional'
  END as customer_tier,
  c.credit_limit,
  c.total_credit as current_balance,
  c.is_active
FROM public.customers c
LEFT JOIN public.sales s ON c.name = s.customer_name AND s.customer_name != 'Walk-in' AND s.status = 'completed'
GROUP BY c.tenant_id, c.id, c.name, c.phone, c.email, c.credit_limit, c.total_credit, c.is_active
ORDER BY total_spent DESC;

-- Inventory Analytics View
CREATE OR REPLACE VIEW vw_inventory_analytics AS
SELECT 
  COUNT(*) as total_products,
  COUNT(CASE WHEN p.is_active = TRUE THEN 1 END) as active_products,
  COUNT(CASE WHEN p.stock_quantity <= 0 THEN 1 END) as out_of_stock,
  COUNT(CASE WHEN p.stock_quantity > 0 AND p.stock_quantity <= p.min_stock_level THEN 1 END) as critical_stock_items,
  COUNT(CASE WHEN p.stock_quantity > p.min_stock_level AND p.stock_quantity < (p.min_stock_level * 3) THEN 1 END) as low_stock_items,
  COUNT(CASE WHEN p.stock_quantity >= (p.min_stock_level * 5) THEN 1 END) as overstock_items,
  SUM(p.stock_quantity * p.cost_price) as total_inventory_value,
  SUM(p.stock_quantity * p.selling_price) as total_retail_value,
  SUM(p.stock_quantity * (p.selling_price - p.cost_price)) as total_potential_profit,
  AVG(p.stock_quantity) as avg_stock_per_product
FROM public.products p
WHERE p.is_active = TRUE
GROUP BY p.id, p.name, p.barcode, p.stock_quantity, p.cost_price, p.selling_price, p.min_stock_level, p.is_active
ORDER BY total_inventory_value DESC;

-- ============================================================================
-- PART 2: Advanced Analytics Functions
-- ============================================================================

-- Function to calculate sales trends
CREATE OR REPLACE FUNCTION calculate_sales_trends(
  p_tenant_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL,
  p_period TEXT DEFAULT 'daily' -- 'daily', 'weekly', 'monthly'
)
RETURNS TABLE (
  period_date DATE,
  gross_sales NUMERIC,
  net_sales NUMERIC,
  transactions_count INTEGER,
  avg_transaction_value NUMERIC,
  unique_customers INTEGER,
  growth_rate NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH sales_data AS (
    SELECT 
      CASE 
        WHEN p_period = 'daily' THEN DATE_TRUNC('day', s.created_at)
        WHEN p_period = 'weekly' THEN DATE_TRUNC('week', s.created_at)
        WHEN p_period = 'monthly' THEN DATE_TRUNC('month', s.created_at)
      END as period_date,
      SUM(s.total_amount) as gross_sales,
      SUM(s.sub_total) as net_sales,
      COUNT(*) as transactions_count,
      AVG(s.total_amount) as avg_transaction_value,
      COUNT(DISTINCT CASE WHEN s.customer_name != 'Walk-in' THEN s.customer_name END) as unique_customers
    FROM public.sales s
    LEFT JOIN public.branches b ON s.branch_id = b.id
    WHERE b.tenant_id = p_tenant_id
      AND (p_branch_id IS NULL OR s.branch_id = p_branch_id)
      AND (p_start_date IS NULL OR DATE(s.created_at) >= p_start_date)
      AND (p_end_date IS NULL OR DATE(s.created_at) <= p_end_date)
      AND s.status = 'completed'
    GROUP BY period_date
  )
  SELECT 
    sd.period_date::DATE,
    sd.gross_sales,
    sd.net_sales,
    sd.transactions_count,
    sd.avg_transaction_value,
    sd.unique_customers,
    CASE 
      WHEN LAG(sd.net_sales, 1) OVER (ORDER BY sd.period_date) > 0
      THEN ROUND(((sd.net_sales - LAG(sd.net_sales, 1) OVER (ORDER BY sd.period_date)) / 
                  LAG(sd.net_sales, 1) OVER (ORDER BY sd.period_date)) * 100, 2)
      ELSE NULL
    END as growth_rate
  FROM sales_data sd
  ORDER BY sd.period_date DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to get top performing products
CREATE OR REPLACE FUNCTION get_top_products(
  p_tenant_id UUID,
  p_branch_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 10,
  p_period TEXT DEFAULT '30 days' -- '7 days', '30 days', '90 days', '1 year'
)
RETURNS TABLE (
  product_id UUID,
  product_name TEXT,
  category TEXT,
  brand TEXT,
  total_units_sold BIGINT,
  total_revenue NUMERIC,
  total_profit NUMERIC,
  profit_margin_percent NUMERIC,
  rank_position INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH product_sales AS (
    SELECT 
      p.id as product_id,
      p.name as product_name,
      COALESCE(c.name, 'Uncategorized') as category,
      COALESCE(SUM(si.quantity), 0) as total_units_sold,
      COALESCE(SUM(si.total_price), 0) as total_revenue,
      COALESCE(SUM(si.total_price - (si.quantity * p.cost_price)), 0) as total_profit,
      CASE 
        WHEN COALESCE(SUM(si.quantity * p.cost_price), 0) > 0
        THEN ROUND(((COALESCE(SUM(si.total_price), 0) - COALESCE(SUM(si.quantity * p.cost_price), 0)) / 
                    COALESCE(SUM(si.quantity * p.cost_price), 0)) * 100, 2)
        ELSE NULL
      END as profit_margin_percent,
      RANK() OVER (ORDER BY COALESCE(SUM(si.total_price), 0) DESC) as rank_position
    FROM public.products p
    LEFT JOIN public.categories c ON p.category_id = c.id
    LEFT JOIN public.sale_items si ON p.id = si.product_id
    LEFT JOIN public.sales s ON si.sale_id = s.id
    WHERE (p_branch_id IS NULL OR p.branch_id = p_branch_id)
      AND s.status = 'completed'
      AND s.created_at >= CURRENT_DATE - (p_period::INTERVAL)
    GROUP BY p.id, p.name, c.name
  )
  SELECT 
    ps.product_id,
    ps.product_name,
    ps.category,
    ps.total_units_sold,
    ps.total_revenue,
    ps.total_profit,
    ps.profit_margin_percent,
    ps.rank_position
  FROM product_sales ps
  WHERE ps.rank_position <= p_limit
  ORDER BY ps.rank_position;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate customer lifetime value
CREATE OR REPLACE FUNCTION calculate_customer_lifetime_value(
  p_tenant_id UUID,
  p_customer_id UUID DEFAULT NULL
)
RETURNS TABLE (
  customer_id UUID,
  customer_name TEXT,
  total_orders INTEGER,
  total_spent NUMERIC,
  avg_order_value NUMERIC,
  days_as_customer INTEGER,
  purchase_frequency NUMERIC,
  projected_clv NUMERIC,
  customer_tier TEXT,
  customer_status TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH customer_data AS (
    SELECT 
      c.id as customer_id,
      c.name as customer_name,
      COUNT(DISTINCT s.id) as total_orders,
      COALESCE(SUM(s.sub_total), 0) as total_spent,
      COALESCE(AVG(s.sub_total), 0) as avg_order_value,
      CURRENT_DATE - MIN(s.created_at) as days_as_customer,
      CASE 
        WHEN COUNT(DISTINCT s.id) > 0 
        THEN ROUND(EXTRACT(DAYS FROM CURRENT_DATE - MIN(s.created_at)) / COUNT(DISTINCT s.id), 2)
        ELSE 0
      END as purchase_frequency,
      CASE 
        WHEN COUNT(DISTINCT s.id) >= 3 AND EXTRACT(DAYS FROM CURRENT_DATE - MIN(s.created_at)) > 0
        THEN ROUND((COALESCE(SUM(s.sub_total), 0) / COUNT(DISTINCT s.id)) * 
                  (365 / EXTRACT(DAYS FROM CURRENT_DATE - MIN(s.created_at))), 2)
        ELSE 0
      END as projected_clv,
      CASE 
        WHEN COALESCE(SUM(s.sub_total), 0) >= 50000 THEN 'VIP'
        WHEN COALESCE(SUM(s.sub_total), 0) >= 20000 THEN 'Premium'
        WHEN COALESCE(SUM(s.sub_total), 0) >= 5000 THEN 'Regular'
        ELSE 'Occasional'
      END as customer_tier,
      CASE 
        -- Fixed: Using AGE function for proper interval to integer comparison
        WHEN EXTRACT(DAYS FROM AGE(CURRENT_DATE, MAX(s.created_at))) <= 30 THEN 'Active'
        WHEN EXTRACT(DAYS FROM AGE(CURRENT_DATE, MAX(s.created_at))) <= 90 THEN 'At Risk'
        WHEN EXTRACT(DAYS FROM AGE(CURRENT_DATE, MAX(s.created_at))) <= 180 THEN 'Dormant'
        ELSE 'Inactive'
      END as customer_status
    FROM public.customers c
    LEFT JOIN public.sales s ON c.name = s.customer_name AND s.customer_name != 'Walk-in' AND s.status = 'completed'
    WHERE c.tenant_id = p_tenant_id
      AND (p_customer_id IS NULL OR c.id = p_customer_id)
      AND c.is_active = TRUE
    GROUP BY c.id, c.name
  )
  SELECT 
    cd.customer_id,
    cd.customer_name,
    cd.total_orders,
    cd.total_spent,
    cd.avg_order_value,
    cd.days_as_customer,
    cd.purchase_frequency,
    cd.projected_clv,
    cd.customer_tier,
    cd.customer_status
  FROM customer_data cd
  ORDER BY cd.total_spent DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 3: Real-time Dashboard Metrics
-- ============================================================================

-- Today's Sales Metrics View
CREATE OR REPLACE VIEW vw_today_sales_metrics AS
SELECT 
  b.tenant_id,
  s.branch_id,
  b.name as branch_name,
  COUNT(*) as total_transactions,
  SUM(s.total_amount) as gross_sales,
  SUM(s.discount_amount) as total_discount,
  SUM(s.vat_amount) as total_tax,
  SUM(s.sub_total) as net_sales,
  AVG(s.total_amount) as avg_transaction_value,
  COUNT(DISTINCT CASE WHEN s.customer_name != 'Walk-in' THEN s.customer_name END) as unique_customers,
  COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '1 hour' THEN 1 END) as transactions_last_hour,
  SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '1 hour' THEN s.sub_total END) as sales_last_hour,
  COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '15 minutes' THEN 1 END) as transactions_last_15min,
  SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '15 minutes' THEN s.sub_total END) as sales_last_15min,
  EXTRACT(HOUR FROM CURRENT_TIME) as current_hour,
  CASE 
    WHEN EXTRACT(HOUR FROM CURRENT_TIME) BETWEEN 9 AND 17 THEN 'Peak Hours'
    ELSE 'Off Peak'
  END as time_period
FROM public.sales s
LEFT JOIN public.branches b ON s.branch_id = b.id
WHERE DATE(s.created_at) = CURRENT_DATE
  AND s.status = 'completed'
GROUP BY b.tenant_id, s.branch_id, b.name;

-- Inventory Status Summary View
CREATE OR REPLACE VIEW vw_inventory_status_summary AS
SELECT 
  COUNT(*) as total_products,
  COUNT(CASE WHEN p.is_active = TRUE THEN 1 END) as active_products,
  COUNT(CASE WHEN p.stock_quantity <= 0 THEN 1 END) as out_of_stock,
  COUNT(CASE WHEN p.stock_quantity > 0 AND p.stock_quantity <= p.min_stock_level THEN 1 END) as critical_stock,
  COUNT(CASE WHEN p.stock_quantity > p.min_stock_level AND p.stock_quantity < (p.min_stock_level * 3) THEN 1 END) as low_stock,
  COUNT(CASE WHEN p.stock_quantity >= (p.min_stock_level * 5) THEN 1 END) as overstock,
  COUNT(CASE WHEN p.stock_quantity > p.min_stock_level AND p.stock_quantity < (p.min_stock_level * 5) THEN 1 END) as optimal_stock,
  SUM(p.stock_quantity * p.cost_price) as total_inventory_value,
  ROUND(AVG(p.stock_quantity), 2) as avg_stock_level
FROM public.products p
WHERE p.is_active = TRUE
GROUP BY p.id, p.name, p.barcode, p.stock_quantity, p.cost_price, p.selling_price, p.min_stock_level, p.is_active
ORDER BY total_inventory_value DESC;

-- ============================================================================
-- PART 4: Performance Comparison Views
-- ============================================================================

-- Branch Performance Comparison View
CREATE OR REPLACE VIEW vw_branch_performance_comparison AS
WITH branch_metrics AS (
  SELECT 
    b.tenant_id,
    s.branch_id,
    b.name as branch_name,
    COUNT(*) as total_transactions,
    SUM(s.sub_total) as total_sales,
    AVG(s.total_amount) as avg_transaction_value,
    COUNT(DISTINCT CASE WHEN s.customer_name != 'Walk-in' THEN s.customer_name END) as unique_customers,
    COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as transactions_last_30_days,
    SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '30 days' THEN s.sub_total END) as sales_last_30_days,
    COUNT(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as transactions_last_7_days,
    SUM(CASE WHEN s.created_at >= CURRENT_DATE - INTERVAL '7 days' THEN s.sub_total END) as sales_last_7_days
  FROM public.sales s
  LEFT JOIN public.branches b ON s.branch_id = b.id
  WHERE s.status = 'completed'
  GROUP BY b.tenant_id, s.branch_id, b.name
),
tenant_averages AS (
  SELECT 
    tenant_id,
    AVG(total_sales) as avg_branch_sales,
    AVG(transactions_last_30_days) as avg_branch_transactions_30d,
    AVG(sales_last_30_days) as avg_branch_sales_30d
  FROM branch_metrics
  GROUP BY tenant_id
)
SELECT 
  bm.tenant_id,
  bm.branch_id,
  bm.branch_name,
  bm.total_transactions,
  bm.total_sales,
  bm.avg_transaction_value,
  bm.unique_customers,
  bm.transactions_last_30_days,
  bm.sales_last_30_days,
  bm.transactions_last_7_days,
  bm.sales_last_7_days,
  ta.avg_branch_sales,
  ta.avg_branch_transactions_30d,
  ta.avg_branch_sales_30d,
  ROUND(((bm.total_sales - ta.avg_branch_sales) / ta.avg_branch_sales) * 100, 2) as sales_vs_avg_percent,
  ROUND(((bm.sales_last_30_days - ta.avg_branch_sales_30d) / ta.avg_branch_sales_30d) * 100, 2) as recent_sales_vs_avg_percent,
  RANK() OVER (PARTITION BY bm.tenant_id ORDER BY bm.total_sales DESC) as sales_rank,
  RANK() OVER (PARTITION BY bm.tenant_id ORDER BY bm.sales_last_30_days DESC) as recent_sales_rank
FROM branch_metrics bm
LEFT JOIN tenant_averages ta ON bm.tenant_id = ta.tenant_id
ORDER BY bm.total_sales DESC;

-- ============================================================================
-- PART 5: Indexes for Performance
-- ============================================================================

-- Indexes for analytics views
CREATE INDEX IF NOT EXISTS idx_sales_tenant_date ON public.sales(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_branch_date ON public.sales(branch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_status_date ON public.sales(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_date ON public.sale_items(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_products_tenant_branch ON public.products(tenant_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers(tenant_id);

-- Indexes for analytics functions
CREATE INDEX IF NOT EXISTS idx_sales_analytics ON public.sales(tenant_id, branch_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_sale_items_analytics ON public.sale_items(product_id, sale_id, quantity, total_amount);

-- ============================================================================
-- PART 6: RLS Policies for Analytics Views
-- ============================================================================

-- Enable RLS on analytics views (through underlying tables)
-- Note: Views inherit RLS from their base tables, so we don't need separate policies

-- Grant access to analytics views for authenticated users
GRANT SELECT ON vw_daily_sales_summary TO authenticated;
GRANT SELECT ON vw_monthly_sales_performance TO authenticated;
GRANT SELECT ON vw_product_performance TO authenticated;
GRANT SELECT ON vw_customer_analytics TO authenticated;
GRANT SELECT ON vw_inventory_analytics TO authenticated;
GRANT SELECT ON vw_today_sales_metrics TO authenticated;
GRANT SELECT ON vw_inventory_status_summary TO authenticated;
GRANT SELECT ON vw_branch_performance_comparison TO authenticated;

-- Grant execute permissions on analytics functions
GRANT EXECUTE ON FUNCTION calculate_sales_trends TO authenticated;
GRANT EXECUTE ON FUNCTION get_top_products TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_customer_lifetime_value TO authenticated;

-- ============================================================================
-- PART 7: Materialized Views for Heavy Analytics
-- ============================================================================

-- Materialized view for daily sales summary (refresh daily)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_sales_summary AS
SELECT * FROM vw_daily_sales_summary;

-- Create unique index for materialized view refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_sales_summary_unique 
ON mv_daily_sales_summary (sale_date, tenant_id, branch_id);

-- Materialized view for monthly performance (refresh monthly)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_sales_performance AS
SELECT * FROM vw_monthly_sales_performance;

-- Create unique index for materialized view refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_monthly_performance_unique 
ON mv_monthly_sales_performance (month, tenant_id, branch_id);

-- Materialized view for product performance (refresh weekly)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_product_performance AS
SELECT * FROM vw_product_performance;

-- Create unique index for materialized view refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_product_performance_unique 
ON mv_product_performance (product_id, tenant_id);

-- Grant access to materialized views
GRANT SELECT ON mv_daily_sales_summary TO authenticated;
GRANT SELECT ON mv_monthly_sales_performance TO authenticated;
GRANT SELECT ON mv_product_performance TO authenticated;

-- ============================================================================
-- PART 8: Refresh Functions for Materialized Views
-- ============================================================================

-- Function to refresh all analytics materialized views
CREATE OR REPLACE FUNCTION refresh_analytics_views()
RETURNS VOID AS $$
BEGIN
  RAISE NOTICE 'Refreshing analytics materialized views...';
  
  -- Refresh daily sales summary
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales_summary;
  RAISE NOTICE 'Daily sales summary refreshed';
  
  -- Refresh monthly performance
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_sales_performance;
  RAISE NOTICE 'Monthly performance refreshed';
  
  -- Refresh product performance
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_product_performance;
  RAISE NOTICE 'Product performance refreshed';
  
  RAISE NOTICE 'All analytics views refreshed successfully';
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION refresh_analytics_views TO authenticated;

-- Create scheduled refresh function (can be called by cron job)
CREATE OR REPLACE FUNCTION scheduled_analytics_refresh()
RETURNS VOID AS $$
BEGIN
  PERFORM refresh_analytics_views();
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION scheduled_analytics_refresh TO authenticated;
