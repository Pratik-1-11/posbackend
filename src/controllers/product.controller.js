import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { checkLimit } from '../utils/subscriptionLimiter.js';
import { scopeToTenant, addTenantToPayload, ensureTenantOwnership, logTenantAction } from '../utils/tenantQuery.js';

export const list = async (req, res, next) => {
  try {
    let query = supabase
      .from('products')
      .select('*, categories(name), suppliers(name)')
      .eq('is_active', true)
      .order('name');

    query = scopeToTenant(query, req, 'products');

    const { data: products, error } = await query;

    if (error) throw error;

    res.status(StatusCodes.OK).json({
      status: 'success',
      results: products.length,
      data: { products },
    });
  } catch (err) {
    next(err);
  }
};

export const getOne = async (req, res, next) => {
  try {
    const { id } = req.params;
    let query = supabase
      .from('products')
      .select('*, categories(name), suppliers(name)')
      .eq('id', id);

    query = scopeToTenant(query, req, 'products');

    const { data: product, error } = await query.single();

    if (error || !product) {
      return res.status(StatusCodes.NOT_FOUND).json({
        status: 'error',
        message: 'Product not found',
      });
    }

    res.status(StatusCodes.OK).json({ status: 'success', data: { product } });
  } catch (err) {
    next(err);
  }
};

export const create = async (req, res, next) => {
  try {
    if (req.tenant && !req.tenant.isSuperAdmin) {
      await checkLimit(req.tenant.id, req.tenant.tier, 'products');
    }

    const {
      name,
      barcode,
      category,
      price,
      costPrice,
      stock,
      minQuantity,
      image,
      description
    } = req.body;

    // ============================================================================
    // CRITICAL VALIDATION (Security Fix #5)
    // ============================================================================

    // Validate name
    if (!name || name.trim() === '') {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Product name is required'
      });
    }

    if (name.length > 200) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Product name cannot exceed 200 characters'
      });
    }

    // Validate prices
    if (price === undefined || price === null || typeof price !== 'number') {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Selling price is required and must be a number'
      });
    }

    if (price < 0) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Selling price cannot be negative'
      });
    }

    if (price > 10000000) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Selling price exceeds maximum allowed value (10,000,000)'
      });
    }

    if (costPrice !== undefined && costPrice !== null) {
      if (typeof costPrice !== 'number' || costPrice < 0) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: 'Cost price must be a non-negative number'
        });
      }

      if (costPrice > 10000000) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: 'Cost price exceeds maximum allowed value (10,000,000)'
        });
      }
    }

    // Validate stock
    if (stock === undefined || stock === null || typeof stock !== 'number') {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Stock quantity is required and must be a number'
      });
    }

    if (stock < 0) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Stock quantity cannot be negative'
      });
    }

    if (!Number.isInteger(stock)) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Stock quantity must be an integer'
      });
    }

    if (stock > 1000000) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Stock quantity exceeds maximum allowed value (1,000,000)'
      });
    }

    // Validate minQuantity
    if (minQuantity !== undefined && minQuantity !== null) {
      if (typeof minQuantity !== 'number' || minQuantity < 0 || !Number.isInteger(minQuantity)) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: 'Minimum quantity must be a non-negative integer'
        });
      }
    }

    const image_url = req.file ? req.file.path : (image || null);

    let category_id = null;
    if (category) {
      let catQuery = supabase
        .from('categories')
        .select('id')
        .ilike('name', category);
      catQuery = scopeToTenant(catQuery, req, 'categories');
      const { data: existingCategory } = await catQuery.single();

      if (existingCategory) {
        category_id = existingCategory.id;
      } else {
        const newCatPayload = addTenantToPayload({ name: category }, req);
        const { data: newCategory } = await supabase
          .from('categories')
          .insert(newCatPayload)
          .select('id')
          .single();
        if (newCategory) category_id = newCategory.id;
      }
    }

    const safeBarcode = (barcode && barcode.trim() !== "") ? barcode : null;

    let dbPayload = {
      name,
      barcode: safeBarcode,
      category_id,
      selling_price: price,
      cost_price: costPrice,
      stock_quantity: stock,
      min_stock_level: minQuantity || 5,
      description,
      image_url: image_url
    };

    dbPayload = addTenantToPayload(dbPayload, req);

    const { data: created, error: productError } = await supabase
      .from('products')
      .insert(dbPayload)
      .select('*, categories(name)')
      .single();

    if (productError) {
      console.error('[ProductController] Insert failed for product:', name);
      console.error('[ProductController] Payload:', JSON.stringify(dbPayload, null, 2));
      console.error('[ProductController] Error:', JSON.stringify(productError, null, 2));

      if (productError.code === '23505') {
        const duplicateMsg = safeBarcode
          ? `A product with barcode "${safeBarcode}" already exists in your store.`
          : 'A duplicate product already exists.';

        return res.status(StatusCodes.CONFLICT).json({
          status: 'error',
          message: duplicateMsg,
          field: 'barcode',
          value: safeBarcode
        });
      }
      throw productError;
    }

    await logTenantAction(supabase, req, 'CREATE', 'product', created.id, { name: created.name });

    res.status(StatusCodes.CREATED).json({ status: 'success', data: { product: created } });
  } catch (err) {
    next(err);
  }
};

export const update = async (req, res, next) => {
  try {
    const { id } = req.params;
    await ensureTenantOwnership(supabase, req, 'products', id);

    const {
      name,
      barcode,
      category,
      price,
      costPrice,
      stock,
      minQuantity,
      isActive,
      description
    } = req.body;

    const image_url = req.file ? req.file.path : undefined;

    let category_id;
    if (category) {
      let catQuery = supabase
        .from('categories')
        .select('id')
        .ilike('name', category);
      catQuery = scopeToTenant(catQuery, req, 'categories');
      const { data: existingCategory } = await catQuery.single();

      if (existingCategory) {
        category_id = existingCategory.id;
      } else {
        const newCatPayload = addTenantToPayload({ name: category }, req);
        const { data: newCategory } = await supabase
          .from('categories')
          .insert(newCatPayload)
          .select('id')
          .single();
        if (newCategory) category_id = newCategory.id;
      }
    }

    const updatePayload = { updated_at: new Date() };
    if (name !== undefined) updatePayload.name = name;
    if (barcode !== undefined) updatePayload.barcode = barcode;
    if (category_id !== undefined) updatePayload.category_id = category_id;
    if (price !== undefined) updatePayload.selling_price = price;
    if (costPrice !== undefined) updatePayload.cost_price = costPrice;
    if (stock !== undefined) updatePayload.stock_quantity = stock;
    if (minQuantity !== undefined) updatePayload.min_stock_level = minQuantity;
    if (description !== undefined) updatePayload.description = description;
    if (isActive !== undefined) updatePayload.is_active = isActive;
    if (image_url !== undefined) updatePayload.image_url = image_url;

    const { data: product, error } = await supabase
      .from('products')
      .update(updatePayload)
      .eq('id', id)
      .select('*, categories(name)')
      .single();

    if (error) throw error;

    await logTenantAction(supabase, req, 'UPDATE', 'product', id, updatePayload);

    res.status(StatusCodes.OK).json({ status: 'success', data: { product } });
  } catch (err) {
    next(err);
  }
};

export const remove = async (req, res, next) => {
  try {
    const { id } = req.params;
    await ensureTenantOwnership(supabase, req, 'products', id);

    const { error } = await supabase
      .from('products')
      .update({ is_active: false })
      .eq('id', id);

    if (error) throw error;

    await logTenantAction(supabase, req, 'DEACTIVATE', 'product', id);

    res.status(StatusCodes.OK).json({ status: 'success', data: { deleted: true } });
  } catch (err) {
    next(err);
  }
};

export const adjustStock = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { quantity, type, reason } = req.body;

    if (quantity === undefined || !type) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Quantity and Type are required'
      });
    }

    const { data, error } = await supabase.rpc('adjust_stock', {
      p_tenant_id: req.tenant.id,
      p_product_id: id,
      p_user_id: req.user.id,
      p_quantity: parseInt(quantity),
      p_type: type,
      p_reason: reason || 'Manual Adjustment'
    });

    if (error) throw error;

    await logTenantAction(supabase, req, 'STOCK_ADJUSTMENT', 'product', id, { quantity, type, reason });

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        new_stock: data.new_stock,
        movement_id: data.movement_id
      }
    });
  } catch (err) {
    next(err);
  }
};

export const listCategories = async (req, res, next) => {
  try {
    let query = supabase.from('categories').select('*').order('name');
    query = scopeToTenant(query, req, 'categories');

    const { data, error } = await query;
    if (error) throw error;

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: { categories: data }
    });
  } catch (err) {
    next(err);
  }
};
