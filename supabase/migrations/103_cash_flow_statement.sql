
-- Migration: 103_cash_flow_statement.sql
-- Purpose: Implement Indirect Method Cash Flow Statement reporting logic.

CREATE OR REPLACE FUNCTION public.get_cash_flow_statement(
    p_tenant_id UUID, 
    p_start_date DATE, 
    p_end_date DATE
)
RETURNS JSONB AS $$
DECLARE
    v_net_income NUMERIC := 0;
    v_operating_cash JSONB;
    v_investing_cash JSONB;
    v_financing_cash JSONB;
    v_beginning_cash NUMERIC := 0;
    v_ending_cash NUMERIC := 0;
    
    v_total_operating NUMERIC := 0;
    v_total_investing NUMERIC := 0;
    v_total_financing NUMERIC := 0;
BEGIN
    -- 1. Calculate Net Income for the period (Crucial for Indirect Method)
    SELECT COALESCE(SUM(l.credit - l.debit), 0) INTO v_net_income
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id 
      AND e.entry_date >= p_start_date 
      AND e.entry_date <= p_end_date 
      AND a.type IN ('revenue', 'expense');

    -- 2. Operating Activities (Adjustments to Net Income)
    -- This includes changes in working capital (AR, AP, Inventory)
    SELECT jsonb_agg(t), COALESCE(SUM(t.change), 0) INTO v_operating_cash, v_total_operating FROM (
        SELECT a.name, a.code, 
               CASE 
                 WHEN a.type = 'asset' THEN SUM(l.credit - l.debit) -- Asset increase is crash outflow (negative)
                 WHEN a.type = 'liability' THEN SUM(l.debit - l.credit) -- Liability increase is cash inflow (positive)
                 ELSE 0
               END as change
        FROM public.journal_entry_lines l
        JOIN public.journal_entries e ON l.entry_id = e.id
        JOIN public.accounts a ON l.account_id = a.id
        WHERE e.tenant_id = p_tenant_id 
          AND e.entry_date >= p_start_date 
          AND e.entry_date <= p_end_date
          AND a.system_code IN ('AR', 'AP', 'INVENTORY')
        GROUP BY a.name, a.code
    ) t;

    -- 3. Investing Activities (Purchase/Sale of Assets)
    -- In this POS, mostly reflected in manual entries or specific asset account movements
    SELECT jsonb_agg(t), COALESCE(SUM(t.change), 0) INTO v_investing_cash, v_total_investing FROM (
        SELECT a.name, a.code, SUM(l.credit - l.debit) as change
        FROM public.journal_entry_lines l
        JOIN public.journal_entries e ON l.entry_id = e.id
        JOIN public.accounts a ON l.account_id = a.id
        WHERE e.tenant_id = p_tenant_id 
          AND e.entry_date >= p_start_date 
          AND e.entry_date <= p_end_date
          AND a.type = 'asset'
          AND a.system_code NOT IN ('CASH', 'AR', 'INVENTORY') -- Fixed Assets, etc.
        GROUP BY a.name, a.code
    ) t;

    -- 4. Financing Activities (Debt/Equity changes)
    SELECT jsonb_agg(t), COALESCE(SUM(t.change), 0) INTO v_financing_cash, v_total_financing FROM (
        SELECT a.name, a.code, SUM(l.credit - l.debit) as change
        FROM public.journal_entry_lines l
        JOIN public.journal_entries e ON l.entry_id = e.id
        JOIN public.accounts a ON l.account_id = a.id
        WHERE e.tenant_id = p_tenant_id 
          AND e.entry_date >= p_start_date 
          AND e.entry_date <= p_end_date
          AND (a.type = 'equity' OR (a.type = 'liability' AND a.system_code NOT IN ('AP', 'VAT_PAYABLE')))
        GROUP BY a.name, a.code
    ) t;

    -- 5. Cash Balances
    -- Beginning Balance
    SELECT COALESCE(SUM(l.debit - l.credit), 0) INTO v_beginning_cash
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id 
      AND e.entry_date < p_start_date 
      AND a.system_code = 'CASH';

    -- Ending Balance
    SELECT COALESCE(SUM(l.debit - l.credit), 0) INTO v_ending_cash
    FROM public.journal_entry_lines l
    JOIN public.journal_entries e ON l.entry_id = e.id
    JOIN public.accounts a ON l.account_id = a.id
    WHERE e.tenant_id = p_tenant_id 
      AND e.entry_date <= p_end_date 
      AND a.system_code = 'CASH';

    RETURN jsonb_build_object(
        'period', jsonb_build_object('start', p_start_date, 'end', p_end_date),
        'net_income', v_net_income,
        'operating_activities', COALESCE(v_operating_cash, '[]'::jsonb),
        'investing_activities', COALESCE(v_investing_cash, '[]'::jsonb),
        'financing_activities', COALESCE(v_financing_cash, '[]'::jsonb),
        'summary', jsonb_build_object(
            'net_operating_cash', v_net_income + COALESCE(v_total_operating, 0),
            'net_investing_cash', COALESCE(v_total_investing, 0),
            'net_financing_cash', COALESCE(v_total_financing, 0),
            'net_increase_in_cash', (v_net_income + COALESCE(v_total_operating, 0) + COALESCE(v_total_investing, 0) + COALESCE(v_total_financing, 0)),
            'beginning_cash', v_beginning_cash,
            'ending_cash', v_ending_cash
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
