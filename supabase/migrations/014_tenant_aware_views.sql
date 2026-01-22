-- ==========================================
-- SCHEMA PATCH: TENANT-AWARE VIEWS
-- ==========================================

-- 1. Daily Sales Summary
DROP VIEW IF EXISTS daily_sales_summary;
CREATE VIEW daily_sales_summary AS
SELECT 
    tenant_id,
    DATE(created_at) as sale_date, 
    COUNT(id) as total_transactions, 
    SUM(sub_total) as total_sub_total, 
    SUM(discount_amount) as total_discount, 
    SUM(taxable_amount) as total_taxable, 
    SUM(vat_amount) as total_vat, 
    SUM(total_amount) as total_revenue
FROM public.sales 
GROUP BY tenant_id, DATE(created_at) 
ORDER BY sale_date DESC;

-- 2. Cashier Performance
DROP VIEW IF EXISTS cashier_performance;
CREATE VIEW cashier_performance AS
SELECT 
    p.tenant_id,
    p.full_name as cashier_name, 
    s.cashier_id, 
    COUNT(s.id) as total_sales_count, 
    SUM(s.total_amount) as total_revenue_generated
FROM public.sales s 
JOIN public.profiles p ON s.cashier_id = p.id 
GROUP BY p.tenant_id, s.cashier_id, p.full_name;

-- 3. Expense Summary
DROP VIEW IF EXISTS expense_summary;
CREATE VIEW expense_summary AS
SELECT 
    tenant_id,
    DATE(date) as expense_date, 
    category, 
    status, 
    COUNT(id) as total_entries, 
    SUM(amount) as total_amount
FROM public.expenses 
GROUP BY tenant_id, DATE(date), category, status 
ORDER BY expense_date DESC;

-- 4. Purchase Summary
DROP VIEW IF EXISTS purchase_summary;
CREATE VIEW purchase_summary AS
SELECT 
    tenant_id,
    DATE(purchase_date) as purchase_date, 
    supplier_name, 
    status, 
    COUNT(id) as total_entries, 
    SUM(quantity) as total_quantity, 
    SUM(total_amount) as total_spent
FROM public.purchases 
GROUP BY tenant_id, DATE(purchase_date), supplier_name, status 
ORDER BY purchase_date DESC;

-- 5. Product Performance
DROP VIEW IF EXISTS product_performance;
CREATE VIEW product_performance AS
SELECT 
    s.tenant_id,
    si.product_name as name, 
    SUM(si.quantity) as quantity, 
    SUM(si.total_price) as revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
GROUP BY s.tenant_id, si.product_name 
ORDER BY revenue DESC;

