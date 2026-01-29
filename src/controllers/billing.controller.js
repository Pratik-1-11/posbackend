import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

/**
 * Get all invoices (Super Admin view)
 */
export const getAllInvoices = async (req, res, next) => {
    try {
        const { tenantId, status } = req.query;
        let query = supabase
            .from('tenant_invoices')
            .select(`
                *,
                tenant:tenants(name, slug)
            `)
            .order('created_at', { ascending: false });

        if (tenantId) query = query.eq('tenant_id', tenantId);
        if (status) query = query.eq('status', status);

        const { data: invoices, error } = await query;
        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: invoices
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Mark an invoice as paid (Manual payment recording)
 */
export const recordPayment = async (req, res, next) => {
    try {
        const { invoice_id, payment_method, transaction_id } = req.body;

        // 1. Get invoice details
        const { data: invoice, error: invError } = await supabase
            .from('tenant_invoices')
            .select('*')
            .eq('id', invoice_id)
            .single();

        if (invError || !invoice) throw invError || new Error('Invoice not found');

        // 2. Insert payment record
        const { error: payError } = await supabase
            .from('tenant_payments')
            .insert({
                tenant_id: invoice.tenant_id,
                invoice_id,
                amount: invoice.amount,
                payment_method: payment_method || 'manual',
                transaction_id,
                status: 'success'
            });

        if (payError) throw payError;

        // 3. Update invoice status
        const { error: updError } = await supabase
            .from('tenant_invoices')
            .update({
                status: 'paid',
                paid_at: new Date().toISOString()
            })
            .eq('id', invoice_id);

        if (updError) throw updError;

        // 4. Update tenant subscription expiry
        const { data: tenant } = await supabase
            .from('tenants')
            .select('plan_interval, subscription_end_date')
            .eq('id', invoice.tenant_id)
            .single();

        const currentExpiry = tenant.subscription_end_date ? new Date(tenant.subscription_end_date) : new Date();
        const interval = tenant.plan_interval === 'yearly' ? 12 : 1;
        const newExpiry = new Date(currentExpiry);
        newExpiry.setMonth(newExpiry.getMonth() + interval);

        await supabase
            .from('tenants')
            .update({
                subscription_status: 'active',
                is_active: true,
                subscription_end_date: newExpiry.toISOString()
            })
            .eq('id', invoice.tenant_id);

        res.status(StatusCodes.OK).json({
            status: 'success',
            message: 'Payment recorded and subscription extended successfully'
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Run manual system-wide auto-suspension check
 */
export const runMaintenanceCheck = async (req, res, next) => {
    try {
        const { data, error } = await supabase.rpc('check_and_suspend_expired_tenants');
        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            message: `Maintenance check complete. ${data[0]?.suspended_count || 0} tenants suspended.`,
            data
        });
    } catch (err) {
        next(err);
    }
};
