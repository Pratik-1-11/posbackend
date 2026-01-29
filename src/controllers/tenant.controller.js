import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

/**
 * Get current tenant's subscription and store limits
 */
export const getSubscriptionInfo = async (req, res, next) => {
    try {
        const { tenant_id } = req.user;

        const { data: tenant, error } = await supabase
            .from('tenants')
            .select(`
                id, 
                name, 
                subscription_tier, 
                subscription_status, 
                max_stores, 
                current_stores_count, 
                verified,
                plans (
                    name,
                    max_users,
                    max_products,
                    features
                )
            `)
            .eq('id', tenant_id)
            .single();

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: tenant
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Request a subscription tier upgrade
 */
export const requestUpgrade = async (req, res, next) => {
    try {
        const { tenant_id, id: userId } = req.user;
        const { requested_tier, justification, stores_count } = req.body;

        if (!['pro', 'enterprise'].includes(requested_tier)) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Invalid requested tier'
            });
        }

        // 1. Get current tier
        const { data: tenant, error: tenantError } = await supabase
            .from('tenants')
            .select('subscription_tier')
            .eq('id', tenant_id)
            .single();

        if (tenantError) throw tenantError;

        // 2. Create upgrade request
        const { data: request, error: requestError } = await supabase
            .from('tenant_upgrade_requests')
            .insert({
                tenant_id,
                requested_tier,
                current_tier: tenant.subscription_tier,
                business_justification: justification,
                requested_stores_count: stores_count,
                status: 'pending'
            })
            .select()
            .single();

        if (requestError) throw requestError;

        res.status(StatusCodes.CREATED).json({
            status: 'success',
            message: 'Upgrade request submitted successfully',
            data: request
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Get all upgrade requests for the current tenant
 */
export const getMyUpgradeRequests = async (req, res, next) => {
    try {
        const { tenant_id } = req.user;

        const { data: requests, error } = await supabase
            .from('tenant_upgrade_requests')
            .select('*')
            .eq('tenant_id', tenant_id)
            .order('created_at', { ascending: false });

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: requests
        });
    } catch (err) {
        next(err);
    }
};

/**
 * List all branches for the current tenant
 */
export const getBranches = async (req, res, next) => {
    try {
        const { tenant_id } = req.user;

        const { data: branches, error } = await supabase
            .from('branches')
            .select('*')
            .eq('tenant_id', tenant_id)
            .order('name', { ascending: true });

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: branches
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Create a new branch (store)
 */
export const createBranch = async (req, res, next) => {
    try {
        const { tenant_id, id: userId } = req.user;
        const { name, address, phone, email, manager_id } = req.body;

        // 1. Check limits
        const { data: tenant, error: tenantError } = await supabase
            .from('tenants')
            .select('max_stores, current_stores_count')
            .eq('id', tenant_id)
            .single();

        if (tenantError) throw tenantError;

        if (tenant.current_stores_count >= tenant.max_stores) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Store limit reached. Please upgrade your subscription.'
            });
        }

        // 2. Create branch
        const { data: branch, error: branchError } = await supabase
            .from('branches')
            .insert({
                tenant_id,
                name,
                address,
                phone,
                email,
                manager_id: manager_id || userId,
                is_active: true
            })
            .select()
            .single();

        if (branchError) throw branchError;

        // 3. Update tenant store count
        await supabase
            .from('tenants')
            .update({ current_stores_count: tenant.current_stores_count + 1 })
            .eq('id', tenant_id);

        res.status(StatusCodes.CREATED).json({
            status: 'success',
            data: branch
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Update a branch
 */
export const updateBranch = async (req, res, next) => {
    try {
        const { tenant_id } = req.user;
        const { id } = req.params;
        const { name, address, phone, email, manager_id, is_active } = req.body;

        const { data: branch, error } = await supabase
            .from('branches')
            .update({
                name,
                address,
                phone,
                email,
                manager_id,
                is_active,
                updated_at: new Date().toISOString()
            })
            .eq('id', id)
            .eq('tenant_id', tenant_id)
            .select()
            .single();

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: branch
        });
    } catch (err) {
        next(err);
    }
};
