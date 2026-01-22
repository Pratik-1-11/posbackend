import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, addTenantToPayload, ensureTenantOwnership, logTenantAction } from '../utils/tenantQuery.js';

export const list = async (req, res, next) => {
    try {
        let query = supabase
            .from('expenses')
            .select('*')
            .order('date', { ascending: false });

        query = scopeToTenant(query, req, 'expenses');

        const { data: expenses, error } = await query;

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: expenses.length,
            data: { expenses },
        });
    } catch (err) {
        next(err);
    }
};

export const create = async (req, res, next) => {
    try {
        const {
            description,
            amount,
            category,
            date,
            status,
            paymentMethod,
            receiptUrl
        } = req.body;

        let dbPayload = {
            description,
            amount,
            category,
            date: date || new Date().toISOString(),
            status: status || 'pending',
            payment_method: paymentMethod,
            receipt_url: receiptUrl
        };

        dbPayload = addTenantToPayload(dbPayload, req);

        const { data: expense, error } = await supabase
            .from('expenses')
            .insert(dbPayload)
            .select('*')
            .single();

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'CREATE_EXPENSE', 'expenses', expense.id, { amount, category });

        res.status(StatusCodes.CREATED).json({ status: 'success', data: { expense } });
    } catch (err) {
        next(err);
    }
};

export const update = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'expenses', id);

        const {
            description,
            amount,
            category,
            date,
            status,
            paymentMethod,
            receiptUrl
        } = req.body;

        const updatePayload = {};
        if (description !== undefined) updatePayload.description = description;
        if (amount !== undefined) updatePayload.amount = amount;
        if (category !== undefined) updatePayload.category = category;
        if (date !== undefined) updatePayload.date = date;
        if (status !== undefined) updatePayload.status = status;
        if (paymentMethod !== undefined) updatePayload.payment_method = paymentMethod;
        if (receiptUrl !== undefined) updatePayload.receipt_url = receiptUrl;

        const { data: expense, error } = await supabase
            .from('expenses')
            .update(updatePayload)
            .eq('id', id)
            .select('*')
            .single();

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'UPDATE_EXPENSE', 'expenses', id, updatePayload);

        res.status(StatusCodes.OK).json({ status: 'success', data: { expense } });
    } catch (err) {
        next(err);
    }
};

export const remove = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'expenses', id);

        const { error } = await supabase
            .from('expenses')
            .delete()
            .eq('id', id);

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'DELETE_EXPENSE', 'expenses', id);

        res.status(StatusCodes.OK).json({ status: 'success', data: null });
    } catch (err) {
        next(err);
    }
};
