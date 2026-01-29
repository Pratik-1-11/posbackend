import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

/**
 * Middleware to check if a tenant has access to a specific feature
 * @param {string} featureKey - The feature key to check (e.g., 'inventory_v2', 'api_access')
 */
export const checkFeatureAccess = (featureKey) => async (req, res, next) => {
    try {
        const { tenant_id } = req.user;

        if (!tenant_id) {
            return res.status(StatusCodes.UNAUTHORIZED).json({
                status: 'error',
                message: 'Tenant identity not found in request context'
            });
        }

        // Fetch tenant with plan features
        const { data: tenant, error } = await supabase
            .from('tenants')
            .select(`
                id,
                plans (
                    features
                )
            `)
            .eq('id', tenant_id)
            .single();

        if (error || !tenant) {
            return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
                status: 'error',
                message: 'Failed to verify tenant feature access'
            });
        }

        const features = tenant.plans?.features || {};

        if (!features[featureKey]) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: `Access Denied: Your current plan does not include the ${featureKey.replace('_', ' ')} feature.`,
                code: 'FEATURE_LOCKED'
            });
        }

        next();
    } catch (err) {
        next(err);
    }
};

/**
 * Middleware to check if a tenant has exceeded a resource limit
 * @param {string} limitKey - The limit key to check (e.g., 'max_users', 'max_stores')
 */
export const checkResourceLimit = (limitKey) => async (req, res, next) => {
    try {
        const { tenant_id } = req.user;

        const { data: hasSpace, error } = await supabase
            .rpc('check_tenant_limit', {
                p_tenant_id: tenant_id,
                p_limit_key: limitKey
            });

        if (error) throw error;

        if (!hasSpace) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: `Limit Reached: You have reached the maximum allowed ${limitKey.replace('max_', '')} for your plan.`,
                code: 'LIMIT_EXCEEDED'
            });
        }

        next();
    } catch (err) {
        next(err);
    }
};
