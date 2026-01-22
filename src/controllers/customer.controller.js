import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, addTenantToPayload, ensureTenantOwnership, logTenantAction } from '../utils/tenantQuery.js';


export const list = async (req, res, next) => {
    try {
        const { page = 1, limit = 50, search = '' } = req.query;
        const from = (page - 1) * limit;
        const to = from + limit - 1;

        let query = supabase
            .from('customers')
            .select('*', { count: 'exact' })
            .order('name');

        query = scopeToTenant(query, req, 'customers');

        if (search) {
            query = query.or(`name.ilike.%${search}%,phone.ilike.%${search}%`);
        }

        const { data: customers, count, error } = await query.range(from, to);

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: customers.length,
            total: count,
            data: { customers },
        });
    } catch (err) {
        next(err);
    }
};

export const getOne = async (req, res, next) => {
    try {
        const { id } = req.params;
        let query = supabase
            .from('customers')
            .select('*')
            .eq('id', id);

        query = scopeToTenant(query, req, 'customers');

        const { data: customer, error } = await query.single();

        if (error || !customer) {
            return res.status(StatusCodes.NOT_FOUND).json({
                status: 'error',
                message: 'Customer not found',
            });
        }

        // Optionally fetch recent transactions?
        // Let's keep it separate or let client request it.

        res.status(StatusCodes.OK).json({ status: 'success', data: { customer } });
    } catch (err) {
        next(err);
    }
};

export const create = async (req, res, next) => {
    try {
        const { name, phone, email, address, creditLimit = 0 } = req.body;

        // Validate required fields
        if (!name || !name.trim()) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Customer name is required',
            });
        }

        // Phone is required for marketing purposes
        if (!phone || !phone.trim()) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Phone number is required for marketing',
            });
        }

        const payload = addTenantToPayload({
            name,
            phone,
            email,
            address,
            credit_limit: creditLimit
        }, req);

        const { data: customer, error } = await supabase
            .from('customers')
            .insert(payload)
            .select()
            .single();

        if (error) {
            if (error.code === '23505') { // Unique violation
                return res.status(StatusCodes.CONFLICT).json({
                    status: 'error',
                    message: 'Customer with this phone number already exists',
                });
            }
            throw error;
        }

        // Audit Log
        await logTenantAction(supabase, req, 'CREATE_CUSTOMER', 'customers', customer.id, { name: customer.name });

        res.status(StatusCodes.CREATED).json({ status: 'success', data: { customer } });

    } catch (err) {
        next(err);
    }
};

export const update = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'customers', id);

        const { name, phone, email, address, isActive, creditLimit } = req.body;

        const updates = {};
        if (name !== undefined) updates.name = name;
        if (phone !== undefined) updates.phone = phone;
        if (email !== undefined) updates.email = email;
        if (address !== undefined) updates.address = address;
        if (isActive !== undefined) updates.is_active = isActive;
        if (creditLimit !== undefined) updates.credit_limit = creditLimit;
        updates.updated_at = new Date();

        const { data: customer, error } = await supabase
            .from('customers')
            .update(updates)
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'UPDATE_CUSTOMER', 'customers', id, updates);

        res.status(StatusCodes.OK).json({ status: 'success', data: { customer } });

    } catch (err) {
        next(err);
    }
};

export const getTransactions = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'customers', id);

        const { data: transactions, error } = await supabase
            .from('customer_transactions')
            .select('*')
            .eq('customer_id', id)
            .order('created_at', { ascending: false });

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data: { transactions } });
    } catch (err) {
        next(err);
    }
};

// Manually add a transaction (Payment or Adjustment)
export const addTransaction = async (req, res, next) => {
    try {
        const { id } = req.params; // Customer ID
        await ensureTenantOwnership(supabase, req, 'customers', id);

        const { type, amount, description } = req.body;

        if (!['payment', 'adjustment', 'opening_balance'].includes(type)) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Invalid transaction type for manual entry.',
            });
        }

        // Use RPC to ensure balance updates
        const { data: transactionId, error } = await supabase.rpc('add_customer_transaction', {
            p_customer_id: id,
            p_type: type,
            p_amount: amount,
            p_description: description || `Manual ${type}`,
            p_reference_id: null,
            p_user_id: req.user.id
        });

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'CUSTOMER_PAYMENT', 'customers', id, { type, amount, description });

        res.status(StatusCodes.CREATED).json({ status: 'success', data: { transactionId } });

    } catch (err) {
        next(err);
    }
};

export const getAgingReport = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;

        // Fetch all customers with positive credit matching tenant
        const { data: customers, error } = await supabase
            .from('customers')
            .select('id, name, total_credit')
            .eq('tenant_id', tenantId)
            .gt('total_credit', 0);

        if (error) throw error;

        // For each customer, find the oldest unpaid sale/transaction
        // This is a simplified aging: we look at when the current balance likely started accumulating
        const agingReport = await Promise.all(customers.map(async (c) => {
            const { data: oldestTx } = await supabase
                .from('customer_transactions')
                .select('created_at')
                .eq('customer_id', c.id)
                .eq('type', 'sale')
                .order('created_at', { ascending: true })
                .limit(1)
                .single();

            const daysOld = oldestTx ? Math.floor((new Date() - new Date(oldestTx.created_at)) / (86400000)) : 0;

            return {
                id: c.id,
                name: c.name,
                balance: c.total_credit,
                daysOld,
                tier: daysOld > 30 ? '30+' : daysOld > 15 ? '15-30' : daysOld > 7 ? '7-15' : '0-7'
            };
        }));

        res.status(StatusCodes.OK).json({ status: 'success', data: { report: agingReport } });
    } catch (err) {
        next(err);
    }
};

export const getHistory = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'customers', id);

        const { data: history, error } = await supabase
            .from('customer_history')
            .select('*')
            .eq('customer_id', id)
            .order('changed_at', { ascending: false });

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data: { history } });
    } catch (err) {
        next(err);
    }
};
