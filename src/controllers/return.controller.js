import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, logTenantAction } from '../utils/tenantQuery.js';

export const createReturn = async (req, res, next) => {
    try {
        const {
            saleId,
            items,
            reason,
            cashierId
        } = req.body;

        const tenantId = req.tenant.id;

        if (!saleId) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Sale ID is required'
            });
        }

        if (!Array.isArray(items) || items.length === 0) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'At least one item must be returned'
            });
        }

        // Call RPC
        const { data: returnResult, error: returnError } = await supabase.rpc('process_pos_return', {
            p_sale_id: saleId,
            p_items: items,
            p_reason: reason || 'N/A',
            p_cashier_id: cashierId || req.user.id
        });

        if (returnError) {
            console.error('Return Processing Error:', returnError);
            throw returnError;
        }

        // Audit Log
        await logTenantAction(supabase, req, 'PROCESS_RETURN', 'returns', returnResult.id, {
            sale_id: saleId,
            refund_amount: returnResult.refund_amount
        });

        res.status(StatusCodes.CREATED).json({
            status: 'success',
            data: {
                return: returnResult
            }
        });

    } catch (err) {
        console.error('Return Creation Failure:', err);
        next(err);
    }
};

export const listReturns = async (req, res, next) => {
    try {
        const { page = 1, limit = 50 } = req.query;
        const from = (page - 1) * limit;
        const to = from + limit - 1;

        let query = supabase
            .from('returns')
            .select('*, return_items(*), sales(invoice_number, customer_name)', { count: 'exact' })
            .order('created_at', { ascending: false });

        query = scopeToTenant(query, req, 'returns');

        const { data: returns, count, error } = await query.range(from, to);

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: returns.length,
            total: count,
            data: { returns },
        });
    } catch (err) {
        next(err);
    }
};

export const getReturn = async (req, res, next) => {
    try {
        const { id } = req.params;
        let query = supabase
            .from('returns')
            .select('*, return_items(*), sales(*)')
            .eq('id', id);

        query = scopeToTenant(query, req, 'returns');

        const { data: returnData, error } = await query.single();

        if (error || !returnData) {
            return res.status(StatusCodes.NOT_FOUND).json({
                status: 'error',
                message: 'Return record not found',
            });
        }

        res.status(StatusCodes.OK).json({ status: 'success', data: { return: returnData } });
    } catch (err) {
        next(err);
    }
};
