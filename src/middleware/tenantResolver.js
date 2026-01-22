/**
 * Tenant Resolution Middleware
 * 
 * Resolves the current user's tenant and attaches it to the request object.
 * Must run after authentication middleware.
 */

import supabase from '../config/supabase.js';

/**
 * Middleware to resolve and attach tenant_id to request
 * @param {Request} req - Express request object
 * @param {Response} res - Express response object
 * @param {Function} next - Express next middleware function
 */
export async function resolveTenant(req, res, next) {
    try {
        const userId = req.user?.id; // Assumes auth middleware has set req.user

        if (!userId) {
            return res.status(401).json({
                error: 'Unauthorized',
                message: 'User authentication required'
            });
        }

        // Fetch user profile with tenant information
        const { data: profile, error } = await supabase
            .from('profiles')
            .select(`
        id,
        tenant_id,
        role,
        full_name,
        email,
        tenants:tenant_id (
          id,
          name,
          slug,
          type,
          is_active,
          subscription_status,
          subscription_tier
        )
      `)
            .eq('id', userId)
            .single();

        if (error) {
            console.error('Tenant resolution error:', error);
            console.error('resolveTenant failed for user:', userId);
            return res.status(500).json({
                error: 'Failed to resolve user profile',
                details: error.message
            });
        }

        const tenant = profile.tenants;

        if (!tenant) {
            return res.status(403).json({
                error: 'Account Error',
                message: 'Your account is not associated with any store.'
            });
        }

        // Check if user is active
        if (profile.is_active === false) {
            return res.status(403).json({
                error: 'Account disabled',
                message: 'Your account has been disabled. Please contact your administrator.'
            });
        }


        // Check if tenant is active
        if (!tenant.is_active) {
            return res.status(403).json({
                error: 'Tenant suspended',
                message: 'Your organization account has been suspended. Please contact support.'
            });
        }

        // Check subscription status
        if (tenant.subscription_status === 'cancelled') {
            return res.status(403).json({
                error: 'Subscription cancelled',
                message: 'Your subscription has been cancelled. Please renew to continue.'
            });
        }

        if (tenant.subscription_status === 'suspended') {
            return res.status(403).json({
                error: 'Subscription suspended',
                message: 'Your subscription is suspended. Please contact billing.'
            });
        }

        // Check for subscription expiry
        if (tenant.subscription_end_date) {
            const expiryDate = new Date(tenant.subscription_end_date);
            const now = new Date();
            if (expiryDate < now) {
                return res.status(403).json({
                    error: 'Subscription expired',
                    message: `Your subscription expired on ${expiryDate.toLocaleDateString()}. Please renew to continue services.`,
                    expired: true
                });
            }
        }

        // Attach tenant context to request
        req.tenant = {
            id: profile.tenant_id,
            name: tenant.name,
            slug: tenant.slug,
            type: tenant.type,
            tier: tenant.subscription_tier,
            isSuperAdmin: profile.role === 'SUPER_ADMIN' || tenant.type === 'super'
        };

        req.userRole = profile.role;
        req.userProfile = {
            id: profile.id,
            name: profile.full_name,
            email: profile.email
        };

        next();
    } catch (error) {
        console.error('Tenant resolution middleware error:', error);
        return res.status(500).json({
            error: 'Internal server error',
            message: 'Failed to process tenant information'
        });
    }
}

/**
 * Optional middleware to allow unauthenticated access
 * but still resolve tenant if user is logged in
 */
export async function optionalTenantResolver(req, res, next) {
    if (!req.user?.id) {
        // No user authenticated, skip tenant resolution
        req.tenant = null;
        req.userRole = null;
        return next();
    }

    // User is authenticated, resolve tenant
    return resolveTenant(req, res, next);
}
