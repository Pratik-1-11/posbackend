
-- Migration: 101_balance_sheet_reporting.sql
-- Purpose: Implement aggregated Balance Sheet reporting logic.

CREATE OR REPLACE FUNCTION public.get_balance_sheet(p_tenant_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB AS $$
DECLARE
    v_total_assets NUMERIC := 0;
    v_total_liabilities NUMERIC := 0;
    v_total_equity NUMERIC := 0;
    v_net_income NUMERIC := 0;
    v_asset_details JSONB;
    v_liability_details JSONB;
    v_equity_details JSONB;
BEGIN
    -- 1. Detailed Asset Breakdown
    SELECT jsonb_agg(t) INTO v_asset_details FROM (
        SELECT a.name, a.code, SUM(l.debit - l.credit) as balance
        FROM public.journal_entry_lines l
        JOIN public.journal_entries e ON l.entry_id = e.id
        JOIN public.accounts a ON l.account_id = a.id
        WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type = 'asset'
        GROUP BY a.name, a.code
        HAVING SUM(l.debit - l.credit) != 0
    ) t;

    -- 2. Detailed Liability Breakdown
    SELECT jsonb_agg(t) INTO v_liability_details FROM (
        SELECT a.name, a.code, SUM(l.credit - l.debit) as balance
        FROM public.journal_entry_lines l
        JOIN public.journal_entries e ON l.entry_id = e.id
        JOIN public.accounts a ON l.account_id = a.id
        WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type = 'liability'
        GROUP BY a.name, a.code
        HAVING SUM(l.credit - l.debit) != 0
    ) t;

    -- 3. Detailed Equity Breakdown (Excluding Net Income)
    SELECT jsonb_agg(t) INTO v_equity_details FROM (
        SELECT a.name, a.code, SUM(l.credit - l.debit) as balance
        FROM public.journal_entry_lines l
        JOIN public.journal_entries e ON l.entry_id = e.id
        JOIN public.accounts a ON l.account_id = a.id
        WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type = 'equity'
        GROUP BY a.name, a.code
        HAVING SUM(l.credit - l.debit) != 0
    ) t;

    -- 4. Calculate Totals
    SELECT COALESCE(SUM(l.debit - l.credit), 0) INTO v_total_assets
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type = 'asset';

    SELECT COALESCE(SUM(l.credit - l.debit), 0) INTO v_total_liabilities
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type = 'liability';

    SELECT COALESCE(SUM(l.credit - l.debit), 0) INTO v_total_equity
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type = 'equity';

    -- 5. Calculate Net Income (Retained Earnings for current period)
    -- Revenue (Credit Balance) - Expense (Debit Balance)
    SELECT COALESCE(SUM(l.credit - l.debit), 0) INTO v_net_income
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id AND e.entry_date <= p_date AND a.type IN ('revenue', 'expense');

    RETURN jsonb_build_object(
        'assets', COALESCE(v_asset_details, '[]'::jsonb),
        'liabilities', COALESCE(v_liability_details, '[]'::jsonb),
        'equity', COALESCE(v_equity_details, '[]'::jsonb),
        'retained_earnings', v_net_income,
        'summary', jsonb_build_object(
            'total_assets', v_total_assets,
            'total_liabilities', v_total_liabilities,
            'total_equity', v_total_equity + v_net_income,
            'is_balanced', (v_total_assets = (v_total_liabilities + v_total_equity + v_net_income))
        ),
        'date', p_date
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
