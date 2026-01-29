import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, logTenantAction } from '../utils/tenantQuery.js';

/**
 * Void a sale - Manager only operation
 * - Requires manager authorization
 * - Restores stock
 * - Reverses credit transactions
 * - Creates audit trail
 */
export const voidSale = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { reason, authCode, managerId } = req.body;
        const tenantId = req.tenant.id;
        const userId = req.user.id;
        const userRole = req.user.role;

        console.log(`[Void Sale] Attempt by ${userId} (${userRole}) for sale ${id}`);

        // ============================================================================
        // CRITICAL: Authorization Check
        // ============================================================================
        const authorizedRoles = ['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'];

        if (!authorizedRoles.includes(userRole)) {
            console.warn(`[Void Sale] UNAUTHORIZED: ${userId} (${userRole}) attempted to void sale ${id}`);

            // Log the attempt
            await logTenantAction(supabase, req, 'VOID_ATTEMPT_DENIED', 'sales', id, {
                reason: 'Insufficient permissions',
                attempted_by: userId,
                role: userRole
            });

            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: `Unauthorized: Only managers can void sales. Your role: ${userRole}`,
                requiredRoles: authorizedRoles
            });
        }

        // ============================================================================
        // Validation
        // ============================================================================

        if (!reason || reason.trim().length < 10) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Void reason must be at least 10 characters',
                field: 'reason'
            });
        }

        // Validate UUID format
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        if (!uuidRegex.test(id)) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Invalid sale ID format'
            });
        }

        // ============================================================================
        // Verify Sale Exists and is Owned by Tenant
        // ============================================================================

        let saleQuery = supabase
            .from('sales')
            .select('*, sale_items(*)')
            .eq('id', id);

        saleQuery = scopeToTenant(saleQuery, req, 'sales');

        const { data: sale, error: saleError } = await saleQuery.maybeSingle();

        if (saleError || !sale) {
            console.error('[Void Sale] Sale not found:', saleError);
            return res.status(StatusCodes.NOT_FOUND).json({
                status: 'error',
                message: 'Sale not found or does not belong to your store'
            });
        }

        // ============================================================================
        // Check if Already Voided
        // ============================================================================

        if (sale.status === 'voided') {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'This sale has already been voided',
                voidedAt: sale.updated_at,
                invoice: sale.invoice_number
            });
        }

        // ============================================================================
        // Call RPC Function to Void Sale
        // ============================================================================

        console.log(`[Void Sale] Calling void_sale RPC for ${id}`);

        const { data: result, error: voidError } = await supabase.rpc('void_sale', {
            p_sale_id: id,
            p_voided_by: userId,
            p_reason: reason.trim(),
            p_manager_id: managerId || userId,
            p_auth_code: authCode || null
        });

        if (voidError) {
            console.error('[Void Sale] RPC Error:', voidError);

            // Check if it's an authorization error from the function
            if (voidError.message && voidError.message.includes('Unauthorized')) {
                return res.status(StatusCodes.FORBIDDEN).json({
                    status: 'error',
                    message: voidError.message
                });
            }

            throw voidError;
        }

        console.log(`[Void Sale] SUCCESS: ${sale.invoice_number} voided by ${req.user.full_name}`);

        // ============================================================================
        // Log Action in Audit
        // ============================================================================

        await logTenantAction(supabase, req, 'VOID_SALE', 'sales', id, {
            invoice_number: sale.invoice_number,
            original_amount: sale.total_amount,
            reason: reason,
            items_count: sale.sale_items?.length || 0,
            voided_by: req.user.full_name,
            manager_authorized: managerId ? true : false
        });

        // ============================================================================
        // Response
        // ============================================================================

        res.status(StatusCodes.OK).json({
            status: 'success',
            message: 'Sale voided successfully. Stock has been restored.',
            data: {
                saleId: id,
                invoiceNumber: sale.invoice_number,
                voidedAt: new Date().toISOString(),
                voidedBy: req.user.full_name,
                reason: reason,
                stockRestored: true,
                itemsAffected: sale.sale_items?.length || 0,
                result: result
            }
        });

    } catch (err) {
        console.error('[Void Sale] Error:', err);
        next(err);
    }
};

/**
 * Track invoice print
 * - Increments print count
 * - Logs reprints to audit trail
 */
export const trackPrint = async (req, res, next) => {
    try {
        const { id } = req.params;
        const userId = req.user.id;

        // Validate UUID
        const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
        if (!uuidRegex.test(id)) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Invalid sale ID format'
            });
        }

        // Call RPC to track print
        const { error: printError } = await supabase.rpc('track_invoice_print', {
            p_sale_id: id,
            p_printed_by: userId
        });

        if (printError) {
            console.error('[Track Print] Error:', printError);
            throw printError;
        }

        // Get updated print count
        const { data: sale } = await supabase
            .from('sales')
            .select('print_count, last_printed_at')
            .eq('id', id)
            .single();

        res.status(StatusCodes.OK).json({
            status: 'success',
            message: 'Print tracked successfully',
            data: {
                printCount: sale?.print_count || 1,
                lastPrintedAt: sale?.last_printed_at,
                isReprint: (sale?.print_count || 0) > 1
            }
        });

    } catch (err) {
        console.error('[Track Print] Error:', err);
        next(err);
    }
};

/**
 * Get invoice modifications audit trail
 * - View all voids, reprints, edit attempts
 * - Manager/Admin only
 */
export const getAuditTrail = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { page = 1, limit = 20 } = req.query;
        const from = (page - 1) * limit;
        const to = from + parseInt(limit) - 1;

        // Authorization: Only managers can view audit trail
        const authorizedRoles = ['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'];
        if (!authorizedRoles.includes(req.user.role)) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Unauthorized: Only managers can view audit trails'
            });
        }

        let query = supabase
            .from('invoice_audit_trail')
            .select('*', { count: 'exact' })
            .eq('tenant_id', req.tenant.id)
            .order('modification_date', { ascending: false });

        // Filter by specific sale if provided
        if (id) {
            query = query.eq('sale_id', id);
        }

        const { data: trail, count, error } = await query.range(from, to);

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: trail?.length || 0,
            total: count,
            page: parseInt(page),
            data: { trail }
        });

    } catch (err) {
        console.error('[Audit Trail] Error:', err);
        next(err);
    }
};

/**
 * Get voided sales report
 * - Summary of all voids
 * - For managers/admins only
 */
export const getVoidedSales = async (req, res, next) => {
    try {
        const { startDate, endDate, page = 1, limit = 50 } = req.query;
        const from = (page - 1) * limit;
        const to = from + parseInt(limit) - 1;

        // Authorization
        const authorizedRoles = ['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'];
        if (!authorizedRoles.includes(req.user.role)) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Unauthorized: Only managers can view voided sales'
            });
        }

        let query = supabase
            .from('sales')
            .select('*, sale_items(*)', { count: 'exact' })
            .eq('status', 'voided')
            .eq('tenant_id', req.tenant.id)
            .order('updated_at', { ascending: false });

        // Date filters
        if (startDate) {
            query = query.gte('created_at', startDate);
        }
        if (endDate) {
            query = query.lte('created_at', endDate);
        }

        const { data: voidedSales, count, error } = await query.range(from, to);

        if (error) throw error;

        // Calculate totals
        const totalVoidedAmount = voidedSales?.reduce((sum, sale) => sum + Number(sale.total_amount), 0) || 0;

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: voidedSales?.length || 0,
            total: count,
            page: parseInt(page),
            data: {
                voidedSales,
                summary: {
                    totalVoids: count,
                    totalVoidedAmount,
                    dateRange: { startDate, endDate }
                }
            }
        });

    } catch (err) {
        console.error('[Voided Sales] Error:', err);
        next(err);
    }
};
