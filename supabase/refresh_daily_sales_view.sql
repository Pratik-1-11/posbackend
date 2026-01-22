-- Comprehensive View Refresh
-- This script Drops and Recreates all reporting views to ensure correct column ordering (tenant_id)

-- 1. Daily Sales Summary
DROP VIEW IF EXISTS public.daily_sales_summary CASCADE;
CREATE VIEW public.daily_sales_summary AS
SELECT
    tenant_id,
    date(created_at) AS sale_date,
    count(id) AS total_transactions,
    sum(sub_total) AS total_sub_total,
    sum(discount_amount) AS total_discount,
    sum(taxable_amount) AS total_taxable,
    sum(vat_amount) AS total_vat,
    sum(total_amount) AS total_revenue
FROM
    public.sales
WHERE
    status = 'completed'
GROUP BY
    tenant_id,
    date(created_at);

-- 2. Cashier Performance
DROP VIEW IF EXISTS public.cashier_performance CASCADE;
CREATE VIEW public.cashier_performance AS
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
DROP VIEW IF EXISTS public.expense_summary CASCADE;
CREATE VIEW public.expense_summary AS
SELECT
    tenant_id,
    DATE(date) as expense_date,
    category,
    status,
    COUNT(id) as total_entries,
    SUM(amount) as total_amount
FROM public.expenses
GROUP BY tenant_id, DATE(date), category, status;

-- 4. Purchase Summary
DROP VIEW IF EXISTS public.purchase_summary CASCADE;
CREATE VIEW public.purchase_summary AS
SELECT
    tenant_id,
    DATE(purchase_date) as purchase_date,
    supplier_name,
    status,
    COUNT(id) as total_entries,
    SUM(quantity) as total_quantity,
    SUM(total_amount) as total_spent
FROM public.purchases
GROUP BY tenant_id, DATE(purchase_date), supplier_name, status;

-- 5. Product Performance
DROP VIEW IF EXISTS public.product_performance CASCADE;
CREATE VIEW public.product_performance AS
SELECT
    s.tenant_id,
    si.product_name as name,
    SUM(si.quantity) as quantity,
    SUM(si.total_price) as revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
GROUP BY s.tenant_id, si.product_name;
