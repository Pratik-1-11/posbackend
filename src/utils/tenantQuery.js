/**
 * Tenant Query Utilities
 * 
 * Helper functions for tenant-scoped database queries.
 * Ensures data isolation between tenants.
 */

/**
 * Apply tenant scoping to Supabase query
 * Super Admins bypass tenant filtering
 * 
 * @param {SupabaseQueryBuilder} query - Supabase query builder
 * @param {Request} req - Express request object with tenant context
 * @param {string} tableName - Name of the table being queried (for logging)
 * @returns {SupabaseQueryBuilder} Modified query with tenant filter
 */
export function scopeToTenant(query, req, tableName = 'unknown') {
    // Super Admin sees all data across all tenants
    if (req.tenant?.isSuperAdmin || req.tenant?.isSuperTenant) {
        console.log(`[Tenant Query] Super Admin accessing all ${tableName}`);
        return query;
    }

    // Ensure tenant context exists
    if (!req.tenant?.id) {
        throw new Error('Tenant context missing. This should not happen if middleware is configured correctly.');
    }

    // Apply tenant filter for regular users
    console.log(`[Tenant Query] Filtering ${tableName} for tenant: ${req.tenant.name} (${req.tenant.id})`);
    return query.eq('tenant_id', req.tenant.id);
}

export async function validateTenantOwnership(supabase, tableName, entityId, tenantId) {
    const { data, error } = await supabase
        .from(tableName)
        .select('id, tenant_id')
        .eq('id', entityId)
        .eq('tenant_id', tenantId)
        .single();

    if (error || !data) {
        return false;
    }

    return data.tenant_id === tenantId;
}

export async function ensureTenantOwnership(supabase, req, tableName, entityId) {
    // Super Admin bypass
    if (req.tenant?.isSuperAdmin) {
        return;
    }

    const isValid = await validateTenantOwnership(
        supabase,
        tableName,
        entityId,
        req.tenant.id
    );

    if (!isValid) {
        throw new Error(`${tableName} not found or access denied`);
    }
}

export function addTenantToPayload(data, req) {
    // Super Admin can create entities for any tenant
    // If tenant_id is already in payload, respect it
    if (req.tenant?.isSuperAdmin && data.tenant_id) {
        return data;
    }

    // For regular users, force tenant_id to their own tenant
    return {
        ...data,
        tenant_id: req.tenant.id
    };
}

export function filterByTenant(items, tenantId) {
    if (!Array.isArray(items)) {
        return [];
    }

    return items.filter(item => item.tenant_id === tenantId);
}

export async function validateMultipleTenantOwnership(supabase, tableName, entityIds, tenantId) {
    if (!entityIds || entityIds.length === 0) {
        return { valid: true, invalidIds: [] };
    }

    const { data, error } = await supabase
        .from(tableName)
        .select('id, tenant_id')
        .in('id', entityIds);

    if (error) {
        throw new Error(`Failed to validate ${tableName} ownership: ${error.message}`);
    }

    const invalidIds = [];
    const foundIds = new Set();

    data.forEach(item => {
        foundIds.add(item.id);
        if (item.tenant_id !== tenantId) {
            invalidIds.push(item.id);
        }
    });

    // Check for IDs that weren't found at all
    entityIds.forEach(id => {
        if (!foundIds.has(id)) {
            invalidIds.push(id);
        }
    });

    return {
        valid: invalidIds.length === 0,
        invalidIds
    };
}

export function getTenantQuery(supabase, tableName, req) {
    let query = supabase.from(tableName).select('*');
    return scopeToTenant(query, req, tableName);
}

export async function logTenantAction(supabase, req, action, entityType, entityId, changes = null) {
    try {
        await supabase.from('audit_logs').insert([{
            actor_id: req.user?.id,
            actor_role: req.userRole,
            tenant_id: req.tenant?.id,
            action,
            entity_type: entityType,
            entity_id: entityId,
            changes,
            ip_address: req.ip,
            user_agent: req.headers['user-agent']
        }]);
    } catch (error) {
        console.error('Failed to create audit log:', error);
        // Don't throw error - audit log failure shouldn't break the request
    }
}

export default {
    scopeToTenant,
    validateTenantOwnership,
    ensureTenantOwnership,
    addTenantToPayload,
    filterByTenant,
    validateMultipleTenantOwnership,
    getTenantQuery,
    logTenantAction
};

