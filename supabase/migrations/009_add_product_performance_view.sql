-- Migration: Add Product Performance View
-- Created: 2026-01-01

CREATE OR REPLACE VIEW product_performance AS
SELECT 
  product_name as name,
  SUM(quantity) as quantity,
  SUM(total_price) as revenue
FROM public.sale_items
GROUP BY product_name
ORDER BY revenue DESC;
