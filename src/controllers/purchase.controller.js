import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, addTenantToPayload, ensureTenantOwnership, logTenantAction } from '../utils/tenantQuery.js';

export const list = async (req, res, next) => {
    try {
        let query = supabase
            .from('purchases')
            .select('*')
            .order('purchase_date', { ascending: false });

        query = scopeToTenant(query, req, 'purchases');

        const { data: purchases, error } = await query;

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            results: purchases.length,
            data: { purchases },
        });
    } catch (err) {
        next(err);
    }
};

export const create = async (req, res, next) => {
    try {
        const {
            productName,
            supplierName,
            quantity,
            unitPrice,
            purchaseDate,
            status,
            sku
        } = req.body;

        let dbPayload = {
            product_name: productName,
            supplier_name: supplierName,
            quantity,
            unit_price: unitPrice,
            purchase_date: purchaseDate || new Date().toISOString(),
            status: status || 'pending',
            sku,
            notes: req.body.notes
        };

        dbPayload = addTenantToPayload(dbPayload, req);

        const { data: purchase, error } = await supabase
            .from('purchases')
            .insert(dbPayload)
            .select('*')
            .single();

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'CREATE_PURCHASE', 'purchases', purchase.id, { productName, supplierName, quantity });

        res.status(StatusCodes.CREATED).json({ status: 'success', data: { purchase } });
    } catch (err) {
        next(err);
    }
};

export const update = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'purchases', id);

        const {
            productName,
            supplierName,
            quantity,
            unitPrice,
            purchaseDate,
            status,
            sku
        } = req.body;

        const updatePayload = {};
        if (productName !== undefined) updatePayload.product_name = productName;
        if (supplierName !== undefined) updatePayload.supplier_name = supplierName;
        if (quantity !== undefined) updatePayload.quantity = quantity;
        if (unitPrice !== undefined) updatePayload.unit_price = unitPrice;
        if (purchaseDate !== undefined) updatePayload.purchase_date = purchaseDate;
        if (status !== undefined) updatePayload.status = status;
        if (sku !== undefined) updatePayload.sku = sku;
        if (req.body.notes !== undefined) updatePayload.notes = req.body.notes;

        const { data: purchase, error } = await supabase
            .from('purchases')
            .update(updatePayload)
            .eq('id', id)
            .select('*')
            .single();

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'UPDATE_PURCHASE', 'purchases', id, updatePayload);

        res.status(StatusCodes.OK).json({ status: 'success', data: { purchase } });
    } catch (err) {
        next(err);
    }
};

export const remove = async (req, res, next) => {
    try {
        const { id } = req.params;
        await ensureTenantOwnership(supabase, req, 'purchases', id);

        const { error } = await supabase
            .from('purchases')
            .delete()
            .eq('id', id);

        if (error) throw error;

        // Audit Log
        await logTenantAction(supabase, req, 'DELETE_PURCHASE', 'purchases', id);

        res.status(StatusCodes.OK).json({ status: 'success', data: null });
    } catch (err) {
        next(err);
    }
};
