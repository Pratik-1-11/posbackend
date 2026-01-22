import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, logTenantAction } from '../utils/tenantQuery.js';


export const create = async (req, res, next) => {
  try {
    const {
      items,
      paymentMethod,
      paymentDetails,
      discountAmount = 0,
      customerId,
      customerName,
      idempotencyKey
    } = req.body;

    const tenantId = req.tenant.id;
    console.log(`[OrderController] Creating order for Tenant: ${tenantId}, User: ${req.user.id}`);

    // ============================================================================
    // CRITICAL VALIDATION (Security Fix #2 & #4)
    // ============================================================================

    // Validate idempotency key (REQUIRED to prevent duplicate orders)
    if (!idempotencyKey || idempotencyKey.trim() === '') {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Missing idempotency key. Please retry from the app.'
      });
    }

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(idempotencyKey)) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Invalid idempotency key format. Must be a valid UUID.'
      });
    }

    // Validate items array
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Order must contain at least one item'
      });
    }

    if (items.length > 100) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Order cannot contain more than 100 items'
      });
    }

    // Validate each item
    for (let i = 0; i < items.length; i++) {
      const item = items[i];

      if (!item.productId) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: `Item at index ${i} is missing productId`
        });
      }

      if (!item.quantity || item.quantity <= 0 || !Number.isInteger(item.quantity)) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: `Invalid quantity for item at index ${i}. Must be a positive integer.`
        });
      }

      if (item.quantity > 10000) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: `Quantity too large for item at index ${i}. Maximum is 10,000 units.`
        });
      }
    }

    // Validate discount amount
    if (typeof discountAmount !== 'number' || discountAmount < 0) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Discount amount cannot be negative'
      });
    }

    if (discountAmount > 1000000) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Discount amount exceeds maximum allowed value'
      });
    }

    // Validate Credit Sale
    if ((paymentMethod === 'credit' || (paymentMethod === 'mixed' && paymentDetails?.credit > 0)) && !customerId) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Customer is required for credit payments.',
      });
    }

    // Calculate totals on backend
    const productIds = items.map(i => i.productId);
    let prodQuery = supabase
      .from('products')
      .select('*')
      .in('id', productIds);

    // Strict scoping
    prodQuery = prodQuery.eq('tenant_id', tenantId);

    const { data: products, error: prodError } = await prodQuery;

    if (prodError) throw prodError;

    const foundProductIds = new Set((products || []).map(p => p.id));
    const allFound = items.every(item => foundProductIds.has(item.productId));

    if (!allFound) {
      console.warn(`[OrderController] Product validation failed for Tenant ${tenantId}. Items: ${items.length}, Found: ${foundProductIds.size}`);
      return res.status(StatusCodes.FORBIDDEN).json({
        status: 'error',
        message: 'One or more products are missing or do not belong to your store'
      });
    }

    let subTotal = 0;
    const saleItems = [];

    for (const item of items) {
      const product = products.find(p => p.id === item.productId);

      if (product.stock_quantity < item.quantity) {
        throw new Error(`Insufficient stock for ${product.name}`);
      }

      const lineTotal = Number(product.selling_price) * item.quantity;
      subTotal += lineTotal;

      saleItems.push({
        productId: product.id,
        name: product.name,
        quantity: item.quantity,
        price: product.selling_price,
        total: lineTotal
      });
    }

    const totalAmount = subTotal - discountAmount;

    // CRITICAL SECURITY: Validate discount cannot exceed subtotal
    if (discountAmount > subTotal) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: `Discount amount (${discountAmount}) cannot exceed subtotal (${subTotal})`
      });
    }

    // Prevent negative total
    if (totalAmount < 0) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Total amount cannot be negative'
      });
    }

    const vatAmount = totalAmount - (totalAmount / 1.13);
    const taxableAmount = totalAmount - vatAmount;

    // ============================================================================
    // SECURE ATOMIC RPC (Fix #9: Remove vulnerable p_tenant_id parameter)
    // RPC internally uses get_user_tenant_id() which is SECURE
    // ============================================================================
    // 4. Call RPC (Atomic Transaction)
    // We pass p_tenant_id because we are calling as Service Role
    const { data: saleResult, error: saleError } = await supabase.rpc('process_pos_sale', {
      p_items: saleItems,
      p_customer_id: customerId || null,
      p_cashier_id: req.user.id,
      p_branch_id: req.user.branch_id || null, // Assuming branch_id is on user
      p_discount_amount: discountAmount,
      p_taxable_amount: taxableAmount, // Simplified for now
      p_vat_amount: vatAmount,
      p_total_amount: totalAmount,
      p_payment_method: paymentMethod || 'cash',
      p_payment_details: paymentDetails || {},
      p_customer_name: customerName || 'Walk-in',
      p_idempotency_key: idempotencyKey,
      p_tenant_id: req.tenant.id // ✅ Required for Service Role calls
    });

    if (saleError) {
      console.error('Sale Processing Error:', saleError);
      throw saleError;
    }

    // Supabase RPC result handling
    const resultRaw = Array.isArray(saleResult) ? saleResult[0] : saleResult;

    // Check if result is wrapped in 'sale' key (from new RPC) or flat (legacy)
    const saleData = resultRaw?.sale || resultRaw;

    if (!saleData || !saleData.id) {
      console.error('Unexpected RPC response structure:', saleResult);
      throw new Error('Failed to retrieve sale result from database');
    }

    const responseOrder = {
      id: saleData.id,
      invoice_number: saleData.invoice_number,
      total_amount: totalAmount,
      payment_method: paymentMethod,
      created_at: new Date().toISOString()
    };

    // Audit Log
    await logTenantAction(supabase, req, 'CREATE_SALE', 'sales', saleData.id, {
      invoice_number: saleData.invoice_number,
      total_amount: totalAmount,
      items_count: saleItems.length
    });

    res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: {
        order: responseOrder,
        sale: responseOrder, // Duplicate for backward/forward compatibility
        items: saleItems
      },
    });

  } catch (err) {
    console.error('Order Creation Failure:', err);
    next(err);
  }
};

export const list = async (req, res, next) => {
  try {
    const { customerId, page = 1, limit = 50 } = req.query;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    let query = supabase
      .from('sales')
      .select('*, sale_items(*)', { count: 'exact' })
      .order('created_at', { ascending: false });

    query = scopeToTenant(query, req, 'sales');

    if (customerId) {
      query = query.eq('customer_id', customerId);
    }

    const { data: orders, count, error } = await query.range(from, to);


    if (error) throw error;

    res.status(StatusCodes.OK).json({
      status: 'success',
      results: orders.length,
      total: count,
      data: { orders },
    });
  } catch (err) {
    next(err);
  }
};

export const getOne = async (req, res, next) => {
  try {
    const { id } = req.params;
    let query = supabase
      .from('sales')
      .select('*, sale_items(*)')
      .eq('id', id);

    query = scopeToTenant(query, req, 'sales');

    const { data: order, error } = await query.single();


    if (error || !order) {
      return res.status(StatusCodes.NOT_FOUND).json({
        status: 'error',
        message: 'Order not found',
      });
    }

    res.status(StatusCodes.OK).json({ status: 'success', data: { order } });
  } catch (err) {
    next(err);
  }
};
