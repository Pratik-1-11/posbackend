import supabase from '../config/supabase.js';
import PLANS from '../config/subscriptionPlans.js';

/**
 * Check if a tenant can create more of a specific resource
 * @param {string} tenantId - The UUID of the tenant
 * @param {string} tenantTier - The subscription tier (basic, pro, enterprise)
 * @param {string} resourceName - 'products', 'users', 'customers'
 * @returns {Promise<boolean>} - True if allowed, throws Error if limit reached
 */
export const checkLimit = async (tenantId, tenantTier, resourceName) => {
    // 1. Get Plan Limits
    const plan = PLANS[tenantTier] || PLANS.basic;
    const limit = plan.limits[resourceName];

    // If -1 or missing, assume unlimited (careful with this, usually explicit is better)
    if (limit === undefined) {
        console.warn(`No limit defined for resource: ${resourceName} in tier: ${tenantTier}`);
        return true;
    }

    // 2. Count Current Usage
    let tableName = '';
    switch (resourceName) {
        case 'products': tableName = 'products'; break;
        case 'users': tableName = 'profiles'; break;
        case 'customers': tableName = 'customers'; break;
        default: throw new Error(`Unknown resource type: ${resourceName}`);
    }

    const { count, error } = await supabase
        .from(tableName)
        .select('*', { count: 'exact', head: true })
        .eq('tenant_id', tenantId);

    if (error) {
        console.error('Error counting resources:', error);
        throw new Error('Failed to verify subscription limits');
    }

    // 3. Compare
    console.log(`[Subscription Check] Tenant: ${tenantId}, Resource: ${resourceName}, Used: ${count}, Limit: ${limit}`);

    if (count >= limit) {
        const error = new Error(`Subscription limit reached for ${resourceName}. Limit: ${limit}, Used: ${count}`);
        error.statusCode = 403;
        error.code = 'LIMIT_REACHED';
        throw error;
    }

    return true;
};
