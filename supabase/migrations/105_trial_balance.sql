
-- Migration: 105_trial_balance.sql
-- Purpose: Implement Trial Balance reporting logic based on double-entry ledger.

CREATE OR REPLACE FUNCTION public.get_trial_balance(
    p_tenant_id UUID,
    p_date DATE
)
RETURNS TABLE (
    account_name TEXT,
    account_code TEXT,
    account_type TEXT,
    debit_balance NUMERIC,
    credit_balance NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.name as account_name,
        a.code as account_code,
        a.type as account_type,
        CASE 
            WHEN SUM(l.debit - l.credit) > 0 THEN SUM(l.debit - l.credit)
            ELSE 0
        END as debit_balance,
        CASE 
            WHEN SUM(l.credit - l.debit) > 0 THEN SUM(l.credit - l.debit)
            ELSE 0
        END as credit_balance
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id 
      AND e.entry_date <= p_date
    GROUP BY a.name, a.code, a.type
    HAVING SUM(l.debit - l.credit) != 0 OR SUM(l.credit - l.debit) != 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
