import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

/**
 * Combined Authentication and Tenant Resolution Middleware
 * Optimized for PRODUCTION: Performs a single DB lookup for profile + tenant details.
 */
export const requireTenantAuth = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader?.startsWith('Bearer ')) {
            return res.status(StatusCodes.UNAUTHORIZED).json({
                status: 'error',
                message: 'Missing or invalid Authorization header',
            });
        }

        const token = authHeader.slice('Bearer '.length);
        const { data: { user }, error: authError } = await supabase.auth.getUser(token);

        if (authError || !user) {
            console.error(`[UnifiedAuth] Verification failed for token: ${token.substring(0, 10)}... Error:`, authError?.message || 'No user found');
            return res.status(StatusCodes.UNAUTHORIZED).json({
                status: 'error',
                message: 'Invalid or expired token',
            });
        }

        // SINGLE DB LOOKUP: Fetch profile and tenant in one query
        const { data: profile, error: profileError } = await supabase
            .from('profiles')
            .select(`
        id, role, branch_id, full_name, email, tenant_id, is_active,
        tenants:tenant_id (
          id, name, slug, type, is_active, subscription_status, subscription_tier
        )
      `)
            .eq('id', user.id)
            .single();

        if (profileError || !profile) {
            console.warn(`Auth Error: Profile not found for ${user.id}`);
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'User profile or associated tenant not found.',
            });
        }

        const tenant = profile.tenants;
        if (!tenant) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Your account is not associated with any store.',
            });
        }

        // Tenant Status Checks
        if (!tenant.is_active) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Your organization account is suspended.',
            });
        }

        // User Status Check
        if (profile.is_active === false) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Your user account has been deactivated.',
            });
        }

        // Attach Context
        req.user = {
            id: profile.id,
            email: profile.email,
            role: profile.role,
            tenant_id: profile.tenant_id,
            branch_id: profile.branch_id,
            full_name: profile.full_name,
            is_active: profile.is_active
        };

        req.tenant = {
            id: tenant.id,
            name: tenant.name,
            slug: tenant.slug,
            type: tenant.type,
            tier: tenant.subscription_tier,
            isSuperAdmin: profile.role === 'SUPER_ADMIN' || tenant.type === 'super'
        };

        console.log(`[UnifiedAuth] User ${profile.email} logged in for Tenant ${profile.tenant_id}`);

        next();
    } catch (err) {
        console.error('Unified Auth Middleware Error:', err);
        return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
            status: 'error',
            message: 'Security validation failed',
        });
    }
};
