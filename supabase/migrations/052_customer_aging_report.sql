-- Migration: 052_customer_aging_report.sql
-- Description: View to calculate customer credit aging

CREATE OR REPLACE VIEW public.vw_customer_aging AS
WITH customer_balances AS (
    -- Get current total credit from customers table
    -- total_credit > 0 means the customer owes money
    SELECT 
        id as customer_id,
        name as customer_name,
        phone,
        total_credit as total_due,
        tenant_id
    FROM public.customers
    WHERE total_credit > 0
),
transaction_age AS (
    -- Categorize sales by age
    SELECT 
        customer_id,
        amount,
        created_at,
        EXTRACT(DAY FROM NOW() - created_at) as age_days
    FROM public.customer_transactions
    WHERE type IN ('sale', 'opening_balance', 'adjustment')
      AND amount > 0
)
SELECT 
    cb.tenant_id,
    cb.customer_id,
    cb.customer_name,
    cb.phone,
    cb.total_due,
    COALESCE(SUM(CASE WHEN ta.age_days <= 30 THEN ta.amount ELSE 0 END), 0) as current_0_30,
    COALESCE(SUM(CASE WHEN ta.age_days > 30 AND ta.age_days <= 60 THEN ta.amount ELSE 0 END), 0) as overdue_31_60,
    COALESCE(SUM(CASE WHEN ta.age_days > 60 AND ta.age_days <= 90 THEN ta.amount ELSE 0 END), 0) as overdue_61_90,
    COALESCE(SUM(CASE WHEN ta.age_days > 90 THEN ta.amount ELSE 0 END), 0) as overdue_91_plus,
    -- Calculate "Estimated Debt Age" (Weighted average if needed, but categories are enough)
    MAX(ta.age_days) as oldest_debt_days
FROM customer_balances cb
LEFT JOIN transaction_age ta ON cb.customer_id = ta.customer_id
GROUP BY cb.tenant_id, cb.customer_id, cb.customer_name, cb.phone, cb.total_due;

-- Note: The above is a "Balance Method" simplified. 
-- For a true FIFO aging, we would need to subtract total payments from the oldest sales first.
-- However, categories the sales themselves gives a good enough picture of recent vs old credit activity.
