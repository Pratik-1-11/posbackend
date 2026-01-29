import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

/**
 * Create a new platform announcement
 */
export const createAnnouncement = async (req, res, next) => {
    try {
        const { title, message, type, target_plan_id, ends_at } = req.body;
        const created_by = req.user.id; // Assumes auth middleware populates this

        const { data, error } = await supabase
            .from('platform_announcements')
            .insert({
                title,
                message,
                type,
                target_plan_id,
                ends_at,
                created_by
            })
            .select()
            .single();

        if (error) throw error;

        res.status(StatusCodes.CREATED).json({
            status: 'success',
            data
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Get all active announcements (Admin view can see all)
 */
export const getAnnouncements = async (req, res, next) => {
    try {
        const { data, error } = await supabase
            .from('platform_announcements')
            .select('*')
            .order('created_at', { ascending: false });

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data
        });
    } catch (err) {
        next(err);
    }
};

/**
 * Calc tenant health
 */
export const getTenantHealth = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { data, error } = await supabase.rpc('calculate_tenant_health', { p_tenant_id: id });

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { health_score: data }
        });
    } catch (err) {
        next(err);
    }
};
