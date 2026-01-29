import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, addTenantToPayload, ensureTenantOwnership } from '../utils/tenantQuery.js';

export const listBatches = async (req, res, next) => {
    try {
        const { productId } = req.query;
        let query = supabase.from('product_batches').select('*').order('expiry_date', { ascending: true });
        query = scopeToTenant(query, req, 'product_batches');

        if (productId) {
            query = query.eq('product_id', productId);
        }

        const { data, error } = await query;
        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data: { batches: data } });
    } catch (err) {
        next(err);
    }
};

export const createBatch = async (req, res, next) => {
    try {
        const {
            product_id,
            batch_number,
            cost_price,
            selling_price,
            quantity_received,
            manufacture_date,
            expiry_date,
            branch_id
        } = req.body;

        const tenantId = req.tenant.id;
        const targetBranchId = branch_id || req.user.current_branch_id || (req.user.tenant?.branchId);

        const payload = addTenantToPayload({
            product_id,
            batch_number,
            cost_price,
            selling_price,
            quantity_received,
            quantity_remaining: quantity_received,
            manufacture_date,
            expiry_date,
            branch_id: targetBranchId
        }, req);

        const { data, error } = await supabase.from('product_batches').insert(payload).select().single();
        if (error) throw error;

        // Also update product stock using the rpc
        await supabase.rpc('adjust_branch_stock', {
            p_tenant_id: tenantId,
            p_branch_id: targetBranchId,
            p_product_id: product_id,
            p_user_id: req.user.id,
            p_quantity: parseInt(quantity_received),
            p_type: 'in',
            p_reason: `New Batch: ${batch_number}`
        });

        res.status(StatusCodes.CREATED).json({ status: 'success', data: { batch: data } });
    } catch (err) {
        next(err);
    }
};

export const getExpiringSoon = async (req, res, next) => {
    try {
        const { days = 30 } = req.query;
        const { data, error } = await supabase.rpc('get_expiring_products', {
            p_tenant_id: req.tenant.id,
            p_days_threshold: parseInt(days)
        });

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { batches: data } });
    } catch (err) {
        next(err);
    }
};

export const updateBatchStatus = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { status } = req.body;

        await ensureTenantOwnership(supabase, req, 'product_batches', id);

        const { data, error } = await supabase
            .from('product_batches')
            .update({ status, updated_at: new Date() })
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;
        res.status(StatusCodes.OK).json({ status: 'success', data: { batch: data } });
    } catch (err) {
        next(err);
    }
};
