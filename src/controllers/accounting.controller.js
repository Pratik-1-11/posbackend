import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

export const getJournalEntries = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { startDate, endDate, accountId } = req.query;

        let query = supabase
            .from('journal_entries')
            .select(`
                *,
                journal_entry_lines (
                    *,
                    accounts (name, code)
                )
            `)
            .eq('tenant_id', tenantId);

        if (startDate) query = query.gte('entry_date', startDate);
        if (endDate) query = query.lte('entry_date', endDate);

        const { data: entries, error } = await query.order('entry_date', { ascending: false });

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { entries } });
    } catch (err) {
        next(err);
    }
};

export const getChartOfAccounts = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { data: accounts, error } = await supabase
            .from('accounts')
            .select('*')
            .eq('tenant_id', tenantId)
            .order('code', { ascending: true });

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { accounts } });
    } catch (err) {
        next(err);
    }
};

export const getProfitAndLoss = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { startDate, endDate } = req.query;

        const { data: pnl, error } = await supabase
            .rpc('get_profit_and_loss', {
                p_tenant_id: tenantId,
                p_start_date: startDate || new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0],
                p_end_date: endDate || new Date().toISOString().split('T')[0]
            });

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { pnl } });
    } catch (err) {
        next(err);
    }
};

export const getTrialBalance = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { date } = req.query;

        const { data: balances, error } = await supabase
            .rpc('get_trial_balance', {
                p_tenant_id: tenantId,
                p_date: date || new Date().toISOString().split('T')[0]
            });

        if (error) throw error;

        // Calculate totals
        const summary = balances.reduce((acc, b) => {
            acc.totalDebit += Number(b.debit_balance);
            acc.totalCredit += Number(b.credit_balance);
            return acc;
        }, { totalDebit: 0, totalCredit: 0 });

        res.status(StatusCodes.OK).json({ status: 'success', data: { balances, summary } });
    } catch (err) {
        next(err);
    }
};

export const getBalanceSheet = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { date } = req.query;

        const { data: balanceSheet, error } = await supabase
            .rpc('get_balance_sheet', {
                p_tenant_id: tenantId,
                p_date: date || new Date().toISOString().split('T')[0]
            });

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data: { balanceSheet } });
    } catch (err) {
        next(err);
    }
};

export const getCustomerAging = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { data: aging, error } = await supabase
            .from('vw_customer_aging')
            .select('*')
            .eq('tenant_id', tenantId)
            .order('total_due', { ascending: false });

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data: { aging } });
    } catch (err) {
        next(err);
    }
};

export const getBankReconciliations = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { data: recs, error } = await supabase
            .from('bank_reconciliations')
            .select('*, accounts(name, code)')
            .eq('tenant_id', tenantId)
            .order('statement_date', { ascending: false });

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { reconciliations: recs } });
    } catch (err) {
        next(err);
    }
};

export const getAccountingAuditLogs = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { data: logs, error } = await supabase
            .from('audit_logs')
            .select('*')
            .eq('tenant_id', tenantId)
            .in('entity_type', ['accounts', 'journal_entries', 'journal_entry_lines'])
            .order('created_at', { ascending: false })
            .limit(100);

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { logs } });
    } catch (err) {
        next(err);
    }
};

export const getCashFlowStatement = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { startDate, endDate } = req.query;

        const { data: cashflow, error } = await supabase
            .rpc('get_cash_flow_statement', {
                p_tenant_id: tenantId,
                p_start_date: startDate || new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0],
                p_end_date: endDate || new Date().toISOString().split('T')[0]
            });

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { cashflow } });
    } catch (err) {
        next(err);
    }
};
