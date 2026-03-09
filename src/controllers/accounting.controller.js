import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant } from '../utils/tenantQuery.js';

export const getJournalEntries = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { startDate, endDate, accountId } = req.query;

        let query = supabase
            .from('journal_entries')
            .select(`
                id, reference_id, reference_type, description, entry_date, created_at,
                journal_entry_lines (
                    id, account_id, debit, credit,
                    accounts:account_id ( code, name, type, system_code )
                )
            `)
            .eq('tenant_id', tenantId)
            .order('entry_date', { ascending: false })
            .order('created_at', { ascending: false });

        if (startDate) query = query.gte('entry_date', startDate);
        if (endDate) query = query.lte('entry_date', endDate);

        const { data: entries, error } = await query;
        if (error) throw error;

        // Filter by account if asked
        let filteredEntries = entries;
        if (accountId) {
            filteredEntries = entries.filter(e =>
                e.journal_entry_lines.some(l => l.account_id === accountId)
            );
        }

        res.status(StatusCodes.OK).json({ status: 'success', data: { entries: filteredEntries } });
    } catch (error) {
        next(error);
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
    } catch (error) {
        next(error);
    }
};

export const getProfitAndLoss = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { startDate, endDate } = req.query;

        // Base query for PL lines 
        // Note: For advanced environments we use RPC or edge functions, 
        // Here we sum it up simply natively for the MVP.
        let query = supabase
            .from('journal_entry_lines')
            .select(`
                debit, credit,
                accounts!inner( type, name, code, system_code ),
                journal_entries!inner( entry_date, tenant_id )
            `)
            .eq('journal_entries.tenant_id', tenantId)
            .in('accounts.type', ['revenue', 'expense']);

        if (startDate) query = query.gte('journal_entries.entry_date', startDate);
        if (endDate) query = query.lte('journal_entries.entry_date', endDate);

        const { data: lines, error } = await query;
        if (error) throw error;

        // Calculate
        let totalRevenue = 0;
        let totalCOGS = 0;
        let totalExpenses = 0;
        let salesDiscount = 0;

        lines.forEach(line => {
            const amount = Number(line.credit) - Number(line.debit); // Revenue credit is positive
            if (line.accounts.system_code === 'SALES_REVENUE') totalRevenue += amount;
            else if (line.accounts.system_code === 'SALES_DISCOUNT') salesDiscount += Math.abs(amount); // debits
            else if (line.accounts.system_code === 'COGS') totalCOGS += Math.abs(amount); // diff
            else if (line.accounts.type === 'expense') totalExpenses -= amount; // Expense debit is negative to credit
        });

        const grossProfit = totalRevenue - salesDiscount - totalCOGS;
        const netIncome = grossProfit - totalExpenses;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                totalRevenue,
                salesDiscount,
                totalCOGS,
                grossProfit,
                totalExpenses,
                netIncome
            }
        });
    } catch (error) {
        next(error);
    }
};

export const getTrialBalance = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;

        const { data: lines, error } = await supabase
            .from('journal_entry_lines')
            .select(`
                debit, credit,
                accounts!inner( id, code, name, type ),
                journal_entries!inner( tenant_id )
            `)
            .eq('journal_entries.tenant_id', tenantId);

        if (error) throw error;

        // Group by account
        const accountBalances = {};

        lines.forEach(line => {
            const acctName = `[${line.accounts.code}] ${line.accounts.name}`;
            if (!accountBalances[acctName]) {
                accountBalances[acctName] = {
                    type: line.accounts.type,
                    debit: 0,
                    credit: 0,
                    balance: 0
                };
            }
            accountBalances[acctName].debit += Number(line.debit);
            accountBalances[acctName].credit += Number(line.credit);
        });

        // Resolve normal balances
        let totalDebit = 0;
        let totalCredit = 0;

        const formattedBalances = Object.keys(accountBalances).map(name => {
            const row = accountBalances[name];
            let normalBalance = 0;
            if (['asset', 'expense'].includes(row.type)) {
                normalBalance = row.debit - row.credit;
                totalDebit += normalBalance;
            } else {
                normalBalance = row.credit - row.debit;
                totalCredit += normalBalance;
            }

            return {
                account: name,
                type: row.type,
                debit: ['asset', 'expense'].includes(row.type) ? normalBalance : 0,
                credit: ['liability', 'equity', 'revenue'].includes(row.type) ? normalBalance : 0,
            };
        }).filter(r => r.debit !== 0 || r.credit !== 0);

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                balances: formattedBalances,
                totalDebit,
                totalCredit
            }
        });

    } catch (error) {
        next(error);
    }
};
