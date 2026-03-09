import { supabase } from '../config/supabase.js';
import { StatusCodes } from 'http-status-codes';
import logger from '../utils/logger.js';

/**
 * Get all integrations for a tenant
 */
export const getIntegrations = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;

        const { data, error } = await supabase
            .from('vw_integration_status')
            .select('*')
            .eq('tenant_id', tenantId);

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data });
    } catch (err) {
        next(err);
    }
};

/**
 * Create a new integration
 */
export const createIntegration = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const profileId = req.user.id;
        const { name, integration_type, provider, description, configuration, authentication_type, credentials } = req.body;

        const { data, error } = await supabase
            .from('external_integrations')
            .insert({
                tenant_id: tenantId,
                name,
                integration_type,
                provider,
                description,
                configuration,
                authentication_type,
                credentials,
                created_by: profileId
            })
            .select()
            .single();

        if (error) throw error;

        res.status(StatusCodes.CREATED).json({ status: 'success', data });
    } catch (err) {
        next(err);
    }
};

/**
 * Get all webhooks for a tenant
 */
export const getWebhooks = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;

        const { data, error } = await supabase
            .from('vw_webhook_performance')
            .select('*')
            .eq('tenant_id', tenantId);

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data });
    } catch (err) {
        next(err);
    }
};

/**
 * Create a webhook subscription
 */
export const createWebhook = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const profileId = req.user.id;
        const { name, target_url, events, secret_key } = req.body;

        const { data, error } = await supabase
            .from('webhook_subscriptions')
            .insert({
                tenant_id: tenantId,
                name,
                target_url,
                events,
                secret_key,
                created_by: profileId
            })
            .select()
            .single();

        if (error) throw error;

        res.status(StatusCodes.CREATED).json({ status: 'success', data });
    } catch (err) {
        next(err);
    }
};

/**
 * Trigger a manual sync job
 */
export const triggerSync = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const { integration_id, entity_type, sync_direction } = req.body;

        const { data, error } = await supabase
            .rpc('sync_data_with_external', {
                p_tenant_id: tenantId,
                p_integration_id: integration_id,
                p_entity_type: entity_type,
                p_sync_direction: sync_direction || 'export'
            });

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data });
    } catch (err) {
        next(err);
    }
};

/**
 * Get sync jobs history
 */
export const getSyncJobs = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;

        const { data, error } = await supabase
            .from('vw_sync_job_performance')
            .select('*')
            .eq('tenant_id', tenantId)
            .order('created_at', { ascending: false })
            .limit(50);

        if (error) throw error;

        res.status(StatusCodes.OK).json({ status: 'success', data });
    } catch (err) {
        next(err);
    }
};
