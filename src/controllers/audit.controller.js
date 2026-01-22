import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, ensureTenantOwnership } from '../utils/tenantQuery.js';

export const list = async (req, res, next) => {
    try {
        const { page = 1, limit = 50, entityType, action } = req.query;
        const from = (page - 1) * limit;
        const to = from + limit - 1;

        let query = supabase
            .from('audit_logs')
            .select('*', { count: 'exact' })
            .order('created_at', { ascending: false });

        query = scopeToTenant(query, req, 'audit_logs');

        if (entityType) {
            query = query.eq('entity_type', entityType);
        }
        if (action) {
            query = query.eq('action', action);
        }

        const { data: logs, count, error } = await query.range(from, to);

        if (error) throw error;

        // Enrich logs with actor names via manual join if needed, or simple ID for now is fine
        // Ideally we would join with auth.users or profiles, but profiles is safer.
        // Let's try to fetch actor names if possible in a second step or join?
        // Basic join on profiles:
        // .select('*, profiles(full_name)')

        // Wait, standard supabase join:
        // query = query.select('*, profiles:actor_id(full_name)');
        // But profiles might be in public schema. Yes.

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: logs.length,
            total: count,
            data: { logs },
        });
    } catch (err) {
        next(err);
    }
};

export default {
    list
};
