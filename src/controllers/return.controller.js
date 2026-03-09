import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, logTenantAction } from '../utils/tenantQuery.js';

// Enhanced return controller with full exchange and policy management
export const createReturn = async (req, res, next) => {
    try {
        const {
            saleId,
            items,
            reason,
            cashierId,
            customerId,
            returnType,
            notes
        } = req.body;

        const tenantId = req.tenant.id;
        const branchId = req.user.branch_id;

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

        // Validate return type
        const validReturnTypes = ['refund', 'exchange', 'store_credit'];
        if (returnType && !validReturnTypes.includes(returnType)) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Invalid return type'
            });
        }

        // Calculate total refund amount
        let totalRefundAmount = 0;
        for (const item of items) {
            if (!item.productId || !item.quantity || !item.unitPrice) {
                return res.status(StatusCodes.BAD_REQUEST).json({
                    status: 'error',
                    message: 'Each item must have productId, quantity, and unitPrice'
                });
            }
            totalRefundAmount += item.quantity * item.unitPrice;
        }

        // Check if return requires manager approval
        const { data: policy } = await supabase
            .from('return_policies')
            .select('*')
            .eq('tenant_id', tenantId)
            .eq('is_active', true)
            .single();

        const requiresApproval = (policy?.requires_manager_approval) || 
                                (totalRefundAmount >= (policy?.min_amount_for_approval || 1000));

        // Create return record
        const { data: returnRecord, error: returnError } = await supabase
            .from('returns')
            .insert({
                tenant_id: tenantId,
                branch_id: branchId,
                original_sale_id: saleId,
                customer_id: customerId,
                return_type: returnType || 'refund',
                return_reason: reason || 'N/A',
                total_refund_amount: totalRefundAmount,
                status: requiresApproval ? 'pending' : 'approved',
                notes: notes,
                created_by: req.user.id,
                manager_approval: !requiresApproval
            })
            .select()
            .single();

        if (returnError) {
            console.error('Return creation error:', returnError);
            throw returnError;
        }

        // Add return items
        const returnItems = items.map(item => ({
            return_id: returnRecord.id,
            product_id: item.productId,
            quantity: item.quantity,
            unit_price: item.unitPrice,
            total_amount: item.quantity * item.unitPrice,
            reason: item.reason || '',
            condition: item.condition || 'used',
            exchange_product_id: item.exchangeProductId || null
        }));

        const { error: itemsError } = await supabase
            .from('return_items')
            .insert(returnItems);

        if (itemsError) {
            console.error('Return items creation error:', itemsError);
            // Rollback the return
            await supabase.from('returns').delete().eq('id', returnRecord.id);
            throw itemsError;
        }

        // Process the return using existing RPC if approved
        let processedReturn = null;
        if (!requiresApproval) {
            const { data: processedResult, error: processError } = await supabase.rpc('process_pos_return', {
                p_sale_id: saleId,
                p_items: items,
                p_reason: reason || 'N/A',
                p_cashier_id: cashierId || req.user.id,
                p_tenant_id: tenantId
            });

            if (processError) {
                console.error('Return processing error:', processError);
                throw processError;
            }
            processedReturn = processedResult;
        }

        // Audit Log
        await logTenantAction(supabase, req, 'CREATE_RETURN', 'returns', returnRecord.id, {
            sale_id: saleId,
            return_type: returnType || 'refund',
            refund_amount: totalRefundAmount,
            requires_approval: requiresApproval,
            items_count: items.length
        });

        res.status(StatusCodes.CREATED).json({
            status: 'success',
            data: {
                return: returnRecord,
                processedReturn,
                requiresApproval
            }
        });

    } catch (err) {
        console.error('Return Creation Failure:', err);
        next(err);
    }
};

// Enhanced return controller with full exchange and policy management

// Get returns list with filtering
export const getReturns = async (req, res, next) => {
    try {
        const { 
            status, 
            returnType, 
            customerId, 
            startDate, 
            endDate, 
            page = 1, 
            limit = 20 
        } = req.query;

        const tenantId = req.tenant.id;
        const branchId = req.user.branch_id;

        // Build query
        let query = supabase
            .from('vw_returns_summary')
            .select('*', { count: 'exact' })
            .eq('tenant_id', tenantId);

        // Apply branch filter for non-admin users
        if (req.user.role !== 'super_admin') {
            query = query.eq('branch_id', branchId);
        }

        // Apply filters
        if (status) query = query.eq('status', status);
        if (returnType) query = query.eq('return_type', returnType);
        if (customerId) query = query.eq('customer_id', customerId);
        if (startDate) query = query.gte('created_at', startDate);
        if (endDate) query = query.lte('created_at', endDate);

        // Apply pagination
        const offset = (Number(page) - 1) * Number(limit);
        query = query.range(offset, offset + Number(limit) - 1);

        // Order by creation date
        query = query.order('created_at', { ascending: false });

        const { data: returns, error, count } = await query;

        if (error) {
            console.error('Get returns error:', error);
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                status: 'error',
                message: 'Failed to fetch returns'
            });
        }

        res.json({
            status: 'success',
            data: {
                returns,
                pagination: {
                    page: Number(page),
                    limit: Number(limit),
                    total: count || 0,
                    pages: Math.ceil((count || 0) / Number(limit))
                }
            }
        });

    } catch (error) {
        console.error('Get returns error:', error);
        next(error);
    }
};

// Get single return details
export const getReturnById = async (req, res, next) => {
    try {
        const { id } = req.params;
        const tenantId = req.tenant.id;

        // Get return details
        const { data: returnRecord, error: returnError } = await supabase
            .from('vw_returns_summary')
            .select('*')
            .eq('id', id)
            .eq('tenant_id', tenantId)
            .single();

        if (returnError || !returnRecord) {
            return res.status(StatusCodes.NOT_FOUND).json({
                status: 'error',
                message: 'Return not found'
            });
        }

        // Get return items
        const { data: items, error: itemsError } = await supabase
            .from('vw_return_items_detail')
            .select('*')
            .eq('return_id', id);

        if (itemsError) {
            console.error('Get return items error:', itemsError);
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                status: 'error',
                message: 'Failed to fetch return items'
            });
        }

        // Get exchange transactions if any
        const { data: exchanges, error: exchangesError } = await supabase
            .from('exchange_transactions')
            .select('*')
            .eq('return_id', id);

        if (exchangesError) {
            console.error('Get exchanges error:', exchangesError);
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                status: 'error',
                message: 'Failed to fetch exchange transactions'
            });
        }

        res.json({
            status: 'success',
            data: {
                return: returnRecord,
                items,
                exchanges
            }
        });

    } catch (error) {
        console.error('Get return by ID error:', error);
        next(error);
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
