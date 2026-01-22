/**
 * Example: Tenant-Aware Product Controller
 * 
 * This demonstrates how to refactor existing controllers
 * to support multi-tenancy.
 */

const { createClient } = require('@supabase/supabase-js');
const {
    scopeToTenant,
    ensureTenantOwnership,
    addTenantToPayload,
    validateMultipleTenantOwnership,
    logTenantAction
} = require('../utils/tenantQuery');

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY
);

/**
 * GET /api/products
 * List all products (scoped to tenant)
 */
exports.getAllProducts = async (req, res) => {
    try {
        const { category_id, is_active, search } = req.query;

        // Start with base query
        let query = supabase
            .from('products')
            .select(`
        *,
        categories (
          id,
          name
        ),
        suppliers (
          id,
          name
        )
      `)
            .order('created_at', { ascending: false });

        // Apply tenant scoping (Super Admin bypass handled automatically)
        query = scopeToTenant(query, req, 'products');

        // Apply additional filters
        if (category_id) {
            query = query.eq('category_id', category_id);
        }

        if (is_active !== undefined) {
            query = query.eq('is_active', is_active === 'true');
        }

        if (search) {
            query = query.or(`name.ilike.%${search}%,barcode.ilike.%${search}%`);
        }

        const { data, error, count } = await query;

        if (error) {
            console.error('Error fetching products:', error);
            throw error;
        }

        res.json({
            success: true,
            data,
            count,
            tenant: req.tenant.name
        });
    } catch (error) {
        console.error('Error in getAllProducts:', error);
        res.status(500).json({
            error: 'Failed to fetch products',
            details: error.message
        });
    }
};

/**
 * GET /api/products/:id
 * Get single product by ID (tenant-scoped)
 */
exports.getProduct = async (req, res) => {
    try {
        const { id } = req.params;

        let query = supabase
            .from('products')
            .select(`
        *,
        categories (
          id,
          name,
          description
        ),
        suppliers (
          id,
          name,
          contact_person,
          phone,
          email
        )
      `)
            .eq('id', id);

        // Apply tenant scoping
        query = scopeToTenant(query, req, 'products');

        const { data, error } = await query.single();

        if (error) {
            if (error.code === 'PGRST116') {
                return res.status(404).json({
                    error: 'Product not found',
                    message: 'The requested product does not exist or you do not have access to it'
                });
            }
            throw error;
        }

        res.json({
            success: true,
            data
        });
    } catch (error) {
        console.error('Error in getProduct:', error);
        res.status(500).json({
            error: 'Failed to fetch product',
            details: error.message
        });
    }
};

/**
 * POST /api/products
 * Create new product (automatically scoped to tenant)
 */
exports.createProduct = async (req, res) => {
    try {
        const productData = req.body;

        // Validate required fields
        if (!productData.name || !productData.selling_price) {
            return res.status(400).json({
                error: 'Missing required fields',
                required: ['name', 'selling_price']
            });
        }

        // Validate category and supplier belong to tenant (if provided)
        if (productData.category_id) {
            const categoryValid = await validateMultipleTenantOwnership(
                supabase,
                'categories',
                [productData.category_id],
                req.tenant.id
            );

            if (!categoryValid.valid) {
                return res.status(403).json({
                    error: 'Invalid category',
                    message: 'The selected category does not belong to your store'
                });
            }
        }

        if (productData.supplier_id) {
            const supplierValid = await validateMultipleTenantOwnership(
                supabase,
                'suppliers',
                [productData.supplier_id],
                req.tenant.id
            );

            if (!supplierValid.valid) {
                return res.status(403).json({
                    error: 'Invalid supplier',
                    message: 'The selected supplier does not belong to your store'
                });
            }
        }

        // Add tenant_id to payload
        const dataWithTenant = addTenantToPayload(productData, req);

        // Insert product
        const { data, error } = await supabase
            .from('products')
            .insert([dataWithTenant])
            .select(`
        *,
        categories (
          id,
          name
        ),
        suppliers (
          id,
          name
        )
      `)
            .single();

        if (error) {
            if (error.code === '23505') {
                return res.status(409).json({
                    error: 'Duplicate barcode',
                    message: 'A product with this barcode already exists'
                });
            }
            throw error;
        }

        // Log action
        await logTenantAction(
            supabase,
            req,
            'create',
            'product',
            data.id,
            { product_name: data.name }
        );

        res.status(201).json({
            success: true,
            data,
            message: 'Product created successfully'
        });
    } catch (error) {
        console.error('Error in createProduct:', error);
        res.status(500).json({
            error: 'Failed to create product',
            details: error.message
        });
    }
};

/**
 * PUT /api/products/:id
 * Update product (tenant-scoped)
 */
exports.updateProduct = async (req, res) => {
    try {
        const { id } = req.params;
        const updates = req.body;

        // Ensure product belongs to tenant
        await ensureTenantOwnership(supabase, req, 'products', id);

        // Validate category and supplier if being updated
        if (updates.category_id) {
            const categoryValid = await validateMultipleTenantOwnership(
                supabase,
                'categories',
                [updates.category_id],
                req.tenant.id
            );

            if (!categoryValid.valid) {
                return res.status(403).json({
                    error: 'Invalid category',
                    message: 'The selected category does not belong to your store'
                });
            }
        }

        if (updates.supplier_id) {
            const supplierValid = await validateMultipleTenantOwnership(
                supabase,
                'suppliers',
                [updates.supplier_id],
                req.tenant.id
            );

            if (!supplierValid.valid) {
                return res.status(403).json({
                    error: 'Invalid supplier',
                    message: 'The selected supplier does not belong to your store'
                });
            }
        }

        // Remove tenant_id from updates (prevent changing tenant)
        delete updates.tenant_id;

        // Update product
        const { data, error } = await supabase
            .from('products')
            .update(updates)
            .eq('id', id)
            .eq('tenant_id', req.tenant.id)  // Double-check tenant
            .select(`
        *,
        categories (
          id,
          name
        ),
        suppliers (
          id,
          name
        )
      `)
            .single();

        if (error) {
            if (error.code === 'PGRST116') {
                return res.status(404).json({
                    error: 'Product not found',
                    message: 'The product does not exist or you do not have access to it'
                });
            }
            throw error;
        }

        // Log action
        await logTenantAction(
            supabase,
            req,
            'update',
            'product',
            data.id,
            { updates, product_name: data.name }
        );

        res.json({
            success: true,
            data,
            message: 'Product updated successfully'
        });
    } catch (error) {
        console.error('Error in updateProduct:', error);

        if (error.message.includes('not found or access denied')) {
            return res.status(404).json({
                error: 'Product not found',
                message: error.message
            });
        }

        res.status(500).json({
            error: 'Failed to update product',
            details: error.message
        });
    }
};

/**
 * DELETE /api/products/:id
 * Delete product (soft delete - set is_active = false)
 */
exports.deleteProduct = async (req, res) => {
    try {
        const { id } = req.params;
        const { hard_delete } = req.query; // Super Admin only

        // Ensure product belongs to tenant
        await ensureTenantOwnership(supabase, req, 'products', id);

        if (hard_delete === 'true' && !req.tenant.isSuperAdmin) {
            return res.status(403).json({
                error: 'Forbidden',
                message: 'Hard delete requires Super Admin privileges'
            });
        }

        if (hard_delete === 'true') {
            // Hard delete (Super Admin only)
            const { error } = await supabase
                .from('products')
                .delete()
                .eq('id', id)
                .eq('tenant_id', req.tenant.id);

            if (error) throw error;

            await logTenantAction(
                supabase,
                req,
                'hard_delete',
                'product',
                id,
                { hard_delete: true }
            );

            res.json({
                success: true,
                message: 'Product permanently deleted'
            });
        } else {
            // Soft delete (set is_active = false)
            const { data, error } = await supabase
                .from('products')
                .update({ is_active: false })
                .eq('id', id)
                .eq('tenant_id', req.tenant.id)
                .select()
                .single();

            if (error) throw error;

            await logTenantAction(
                supabase,
                req,
                'delete',
                'product',
                id,
                { product_name: data.name, soft_delete: true }
            );

            res.json({
                success: true,
                data,
                message: 'Product deactivated successfully'
            });
        }
    } catch (error) {
        console.error('Error in deleteProduct:', error);

        if (error.message.includes('not found or access denied')) {
            return res.status(404).json({
                error: 'Product not found',
                message: error.message
            });
        }

        res.status(500).json({
            error: 'Failed to delete product',
            details: error.message
        });
    }
};

/**
 * POST /api/products/bulk-create
 * Create multiple products at once (tenant-scoped)
 */
exports.bulkCreateProducts = async (req, res) => {
    try {
        const { products } = req.body;

        if (!Array.isArray(products) || products.length === 0) {
            return res.status(400).json({
                error: 'Invalid input',
                message: 'Expected array of products'
            });
        }

        // Validate all products
        for (const product of products) {
            if (!product.name || !product.selling_price) {
                return res.status(400).json({
                    error: 'Invalid product data',
                    message: 'Each product must have name and selling_price'
                });
            }
        }

        // Add tenant_id to all products
        const productsWithTenant = products.map(p => addTenantToPayload(p, req));

        // Bulk insert
        const { data, error } = await supabase
            .from('products')
            .insert(productsWithTenant)
            .select();

        if (error) {
            throw error;
        }

        // Log action
        await logTenantAction(
            supabase,
            req,
            'bulk_create',
            'product',
            null,
            { count: data.length }
        );

        res.status(201).json({
            success: true,
            data,
            count: data.length,
            message: `${data.length} products created successfully`
        });
    } catch (error) {
        console.error('Error in bulkCreateProducts:', error);
        res.status(500).json({
            error: 'Failed to create products',
            details: error.message
        });
    }
};

/**
 * GET /api/products/low-stock
 * Get products with stock below minimum threshold
 */
exports.getLowStockProducts = async (req, res) => {
    try {
        let query = supabase
            .from('products')
            .select('*')
            .lte('stock_quantity::int', supabase.raw('min_stock_level'))
            .eq('is_active', true)
            .order('stock_quantity', { ascending: true });

        // Apply tenant scoping
        query = scopeToTenant(query, req, 'products');

        const { data, error } = await query;

        if (error) throw error;

        res.json({
            success: true,
            data,
            count: data.length,
            tenant: req.tenant.name
        });
    } catch (error) {
        console.error('Error in getLowStockProducts:', error);
        res.status(500).json({
            error: 'Failed to fetch low stock products',
            details: error.message
        });
    }
};

module.exports = exports;
