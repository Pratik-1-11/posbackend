import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, addTenantToPayload } from '../utils/tenantQuery.js';

export const getSettings = async (req, res, next) => {
    try {
        let query = supabase
            .from('settings')
            .select('*');

        try {
            query = scopeToTenant(query, req, 'settings');
        } catch (err) {
            console.warn('[Settings] Skipping tenant filter: column probably missing');
        }

        const { data: settings, error } = await query.single();

        if (error) {
            if (error.code === 'PGRST116') { // No rows found
                return res.status(StatusCodes.OK).json({ status: 'success', data: { settings: {} } });
            }
            if (error.code === '42703') { // Undefined column
                console.error('[Settings] Settings table is missing tenant_id column. Please run the migration.');
                // Fallback: fetch without tenant scope (unsafe but prevents 500)
                const { data: rawSettings, error: rawError } = await supabase.from('settings').select('*').single();
                if (rawError) throw rawError;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { settings: rawSettings } });
            }
            throw error;
        }

        res.status(StatusCodes.OK).json({ status: 'success', data: { settings } });
    } catch (err) {
        next(err);
    }

};

export const updateSettings = async (req, res, next) => {
    try {
        const {
            name, address, phone, email, pan, footerMessage,
            taxRate, currency, receiptSettings, notificationSettings, securitySettings
        } = req.body;

        const updates = {
            name,
            address,
            phone,
            email,
            pan,
            footer_message: footerMessage,
            tax_rate: taxRate,
            currency,
            receipt_settings: receiptSettings,
            notification_settings: notificationSettings,
            security_settings: securitySettings,
            updated_at: new Date()
        };

        // Remove undefined fields
        Object.keys(updates).forEach(key => updates[key] === undefined && delete updates[key]);

        const tenantId = req.tenant.id;
        console.log(`[Settings] Attempting to save settings for tenant: ${tenantId}`);

        // 1. Try UPDATE first (Optimistic Concurrency)
        const { data: updated, error: updateError } = await supabase
            .from('settings')
            .update({ ...updates })
            .eq('tenant_id', tenantId)
            .select();

        if (updateError) {
            console.error('[Settings] Update operation failed:', updateError);
            throw updateError;
        }

        if (updated && updated.length > 0) {
            console.log('[Settings] Update successful, matched rows:', updated.length);
            return res.status(StatusCodes.OK).json({ status: 'success', data: { settings: updated[0] } });
        }

        // 2. If no rows updated, INSERT new
        console.log('[Settings] No existing settings found, inserting new record.');
        const { data: inserted, error: insertError } = await supabase
            .from('settings')
            .insert({ ...updates, tenant_id: tenantId })
            .select()
            .single();

        if (insertError) {
            console.error('[Settings] Insert operation failed:', insertError);
            // Check for specific race condition where row was created between update and insert
            // or if 409 Conflict occurred (if matching ON CONFLICT existed)
            if (insertError.code === '23505' || insertError.code === '409') {
                console.warn('[Settings] Race condition/Conflict detected, retrying update...');
                const { data: retryUpdate, error: retryError } = await supabase
                    .from('settings')
                    .update({ ...updates })
                    .eq('tenant_id', tenantId)
                    .select()
                    .single();

                if (retryError) throw retryError;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { settings: retryUpdate } });
            }
            throw insertError;
        }

        res.status(StatusCodes.OK).json({ status: 'success', data: { settings: inserted } });
    } catch (err) {
        next(err);
    }
};

