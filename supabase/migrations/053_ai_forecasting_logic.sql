-- Migration: 053_ai_forecasting_logic.sql
-- Description: Advanced SQL functions for business forecasting using linear regression

-- 1. Sales Forecasting Function
-- Predicts sales for the next N months based on historical data (last 12 months)
CREATE OR REPLACE FUNCTION public.predict_monthly_sales(
  p_tenant_id UUID,
  p_months_forward INTEGER DEFAULT 3
)
RETURNS TABLE (
  forecast_month DATE,
  predicted_revenue NUMERIC,
  confidence_score NUMERIC,
  trend_direction TEXT
) AS $$
DECLARE
  v_slope NUMERIC;
  v_intercept NUMERIC;
  v_last_month_val NUMERIC;
  v_avg_val NUMERIC;
BEGIN
  -- Aggregate monthly sales for the last 12 months
  WITH monthly_data AS (
    SELECT 
      EXTRACT(EPOCH FROM DATE_TRUNC('month', created_at)) as x, -- Time as independent variable
      SUM(sub_total) as y,                                    -- Revenue as dependent variable
      DATE_TRUNC('month', created_at) as m_date
    FROM public.sales
    WHERE tenant_id = p_tenant_id 
      AND status = 'completed'
      AND created_at >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY 1, 3
    ORDER BY 1
  ),
  regression_stats AS (
    SELECT 
      REGR_SLOPE(y, x) as slope,
      REGR_INTERCEPT(y, x) as intercept,
      AVG(y) as avg_y
    FROM monthly_data
  )
  SELECT slope, intercept, avg_y INTO v_slope, v_intercept, v_avg_val FROM regression_stats;

  -- Default to 0 if no data
  v_slope := COALESCE(v_slope, 0);
  v_intercept := COALESCE(v_intercept, 0);

  -- Generate future points
  RETURN QUERY
  SELECT 
    (DATE_TRUNC('month', CURRENT_DATE) + (i || ' month')::INTERVAL)::DATE as forecast_month,
    GREATEST(0, (v_slope * EXTRACT(EPOCH FROM (DATE_TRUNC('month', CURRENT_DATE) + (i || ' month')::INTERVAL))) + v_intercept)::NUMERIC as predicted_revenue,
    CASE WHEN v_avg_val > 0 THEN LEAST(100, (1 - ABS(v_slope * 2592000 / v_avg_val)) * 100) ELSE 0 END::NUMERIC as confidence_score, -- Simplified confidence
    CASE WHEN v_slope > 0 THEN 'up' WHEN v_slope < 0 THEN 'down' ELSE 'stable' END as trend_direction
  FROM generate_series(1, p_months_forward) i;
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. Stock Depletion Prediction
-- Predicts days remaining until stock hits zero based on last 30 days consumption
CREATE OR REPLACE FUNCTION public.predict_stock_depletion(
    p_tenant_id UUID,
    p_product_id UUID
)
RETURNS TABLE (
    product_name TEXT,
    current_stock INTEGER,
    avg_daily_consumption NUMERIC,
    days_remaining INTEGER,
    estimated_depletion_date DATE,
    recommendation TEXT
) AS $$
DECLARE
    v_daily_avg NUMERIC;
    v_stock INTEGER;
    v_pname TEXT;
BEGIN
    -- Get current info
    SELECT name, stock_quantity INTO v_pname, v_stock 
    FROM public.products 
    WHERE id = p_product_id AND tenant_id = p_tenant_id;

    -- Calculate consumption rate (last 30 days)
    SELECT COALESCE(SUM(quantity), 0) / 30.0 INTO v_daily_avg
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    WHERE si.product_id = p_product_id 
      AND s.status = 'completed'
      AND s.created_at >= CURRENT_DATE - INTERVAL '30 days';

    v_daily_avg := COALESCE(v_daily_avg, 0);

    RETURN QUERY
    SELECT 
        v_pname,
        v_stock,
        v_daily_avg,
        CASE WHEN v_daily_avg > 0 THEN FLOOR(v_stock / v_daily_avg)::INTEGER ELSE 999 END,
        CASE WHEN v_daily_avg > 0 THEN (CURRENT_DATE + (FLOOR(v_stock / v_daily_avg) || ' days')::INTERVAL)::DATE ELSE NULL END,
        CASE 
            WHEN v_daily_avg = 0 THEN 'No recent sales. Stock stable.'
            WHEN v_stock / v_daily_avg < 7 THEN 'CRITICAL: Reorder immediately (less than 7 days left)'
            WHEN v_stock / v_daily_avg < 14 THEN 'WARNING: Reorder soon (less than 14 days left)'
            ELSE 'Healthy stock level'
        END;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Top Predictive Insights View
-- Combines various predictive signals into a single dashboard-ready view
CREATE OR REPLACE VIEW public.vw_predictive_insights AS
SELECT 
    p.tenant_id,
    p.id as product_id,
    p.name as product_name,
    p.stock_quantity,
    psd.days_remaining,
    psd.avg_daily_consumption,
    psd.recommendation,
    -- Simple forecast: If we sold X in 30 days, we might sell X * 1.1 next month
    COALESCE((SELECT SUM(total_price) FROM public.sale_items si JOIN public.sales s ON si.sale_id = s.id 
     WHERE si.product_id = p.id AND s.created_at >= CURRENT_DATE - INTERVAL '30 days'), 0) * 1.1 as projected_next_month_revenue
FROM public.products p
CROSS JOIN LATERAL public.predict_stock_depletion(p.tenant_id, p.id) psd
WHERE p.is_active = TRUE;

-- Permissions
GRANT EXECUTE ON FUNCTION public.predict_monthly_sales TO authenticated;
GRANT EXECUTE ON FUNCTION public.predict_stock_depletion TO authenticated;
GRANT SELECT ON public.vw_predictive_insights TO authenticated;
