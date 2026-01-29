import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant } from '../utils/tenantQuery.js';

/**
 * Get current active shift for user
 */
export const getCurrentShift = async (req, res, next) => {
    try {
        const userId = req.user.id;
        const tenantId = req.tenant.id;

        const { data, error } = await supabase
            .from('shift_sessions')
            .select('*')
            .eq('cashier_id', userId)
            .eq('tenant_id', tenantId)
            .eq('status', 'open')
            .maybeSingle();

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: data || null
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Open a new shift
 */
export const openShift = async (req, res, next) => {
    try {
        const { startCash, notes } = req.body;
        const userId = req.user.id;
        const tenantId = req.tenant.id;

        // Check if shift already open
        const { data: existing } = await supabase
            .from('shift_sessions')
            .select('id')
            .eq('cashier_id', userId)
            .eq('tenant_id', tenantId)
            .eq('status', 'open')
            .maybeSingle();

        if (existing) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'You already have an active shift open.'
            });
        }

        const { data, error } = await supabase
            .from('shift_sessions')
            .insert([{
                cashier_id: userId,
                tenant_id: tenantId,
                start_cash: startCash || 0,
                notes,
                status: 'open'
            }])
            .select()
            .single();

        if (error) throw error;

        res.status(StatusCodes.CREATED).json({
            status: 'success',
            data
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Close active shift
 */
export const closeShift = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { actualCash, notes } = req.body;

        const { data, error } = await supabase.rpc('close_shift', {
            p_shift_id: id,
            p_actual_cash: actualCash,
            p_notes: notes
        });

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            message: 'Shift closed successfully',
            data
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Get shift summary / Z-Report
 */
export const getShiftSummary = async (req, res, next) => {
    try {
        const { id } = req.params;

        // Fetch shift details
        const { data: shift, error: shiftError } = await supabase
            .from('shift_sessions')
            .select('*, cashier:profiles(full_name)')
            .eq('id', id)
            .single();

        if (shiftError) throw shiftError;

        // Fetch aggregated sales for this shift
        const { data: sales, error: salesError } = await supabase
            .from('sales')
            .select('total_amount, tax_amount, discount_amount, payment_method, payment_details')
            .eq('shift_id', id)
            .eq('status', 'completed');

        if (salesError) throw salesError;

        // Calculate totals
        const summary = sales.reduce((acc, sale) => {
            acc.totalSales += Number(sale.total_amount);
            acc.totalTax += Number(sale.tax_amount || 0);
            acc.totalDiscount += Number(sale.discount_amount || 0);

            const method = sale.payment_method;
            acc.byMethod[method] = (acc.byMethod[method] || 0) + Number(sale.total_amount);

            return acc;
        }, {
            totalSales: 0,
            totalTax: 0,
            totalDiscount: 0,
            byMethod: {}
        });

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                shift,
                summary
            }
        });
    } catch (err) {
        next(err);
    }
};
