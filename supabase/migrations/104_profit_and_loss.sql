
-- Migration: 104_profit_and_loss.sql
-- Purpose: Implement Profit & Loss reporting logic based on double-entry ledger.

CREATE OR REPLACE FUNCTION public.get_profit_and_loss(
    p_tenant_id UUID,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS TABLE (
    category TEXT,
    account_name TEXT,
    account_code TEXT,
    amount NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.type as category,
        a.name as account_name,
        a.code as account_code,
        CASE 
            WHEN a.type = 'revenue' THEN SUM(l.credit - l.debit)
            WHEN a.type = 'expense' THEN SUM(l.debit - l.credit)
            ELSE 0
        END as amount
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id 
      AND e.entry_date >= p_start_date 
      AND e.entry_date <= p_end_date 
      AND a.type IN ('revenue', 'expense')
    GROUP BY a.type, a.name, a.code
    HAVING SUM(l.credit - l.debit) != 0 OR SUM(l.debit - l.credit) != 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
