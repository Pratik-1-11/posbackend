import { pool } from '../config/db.js';

const normalizePaymentMethod = (pm) => {
  if (!pm) return pm;
  if (pm === 'cash') return 'CASH';
  if (pm === 'card') return 'CARD';
  if (pm === 'qr') return 'MOBILE_PAYMENT';
  return pm;
};

export const createOrder = async ({
  customerName,
  customerEmail,
  customerPhone,
  discountAmount,
  taxAmount,
  paymentMethod,
  notes,
  items,
  createdBy,
}) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const productIds = items.map((i) => Number(i.productId));

    const { rows: products } = await client.query(
      `SELECT id, name, price, quantity_in_stock, is_active
       FROM products
       WHERE id = ANY($1::int[])`,
      [productIds]
    );

    const productById = new Map(products.map((p) => [p.id, p]));

    for (const item of items) {
      const pid = Number(item.productId);
      const product = productById.get(pid);
      if (!product) {
        const err = new Error(`Product not found: ${item.productId}`);
        err.statusCode = 400;
        throw err;
      }
      if (!product.is_active) {
        const err = new Error(`Product is inactive: ${item.productId}`);
        err.statusCode = 400;
        throw err;
      }
      if (product.quantity_in_stock < item.quantity) {
        const err = new Error(`Insufficient stock for product ${product.name}`);
        err.statusCode = 400;
        throw err;
      }
    }

    const subtotal = items.reduce((sum, item) => {
      const p = productById.get(Number(item.productId));
      return sum + Number(p.price) * item.quantity;
    }, 0);

    const totalAmount = subtotal + Number(taxAmount) - Number(discountAmount);

    const { rows: orderRows } = await client.query(
      `INSERT INTO orders
        (customer_name, customer_email, customer_phone, subtotal, tax_amount, discount_amount, total_amount,
         payment_method, payment_status, status, notes, created_by)
       VALUES
        ($1,$2,$3,$4,$5,$6,$7,$8,'PAID','COMPLETED',$9,$10)
       RETURNING id, order_number, customer_name, customer_email, customer_phone,
                 subtotal, tax_amount, discount_amount, total_amount,
                 payment_method, payment_status, status, notes, created_at, created_by`,
      [
        customerName || null,
        customerEmail || null,
        customerPhone || null,
        subtotal,
        taxAmount,
        discountAmount,
        totalAmount,
        normalizePaymentMethod(paymentMethod),
        notes || null,
        createdBy,
      ]
    );

    const order = orderRows[0];

    const insertedItems = [];

    for (const item of items) {
      const product = productById.get(Number(item.productId));
      const { rows } = await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_amount)
         VALUES ($1,$2,$3,$4,0)
         RETURNING id, order_id, product_id, quantity, unit_price, discount_amount, total_price`,
        [order.id, product.id, item.quantity, product.price]
      );

      insertedItems.push(rows[0]);
    }

    await client.query('COMMIT');

    return {
      id: String(order.id),
      orderNumber: order.order_number,
      customerName: order.customer_name,
      customerEmail: order.customer_email,
      customerPhone: order.customer_phone,
      subtotal: Number(order.subtotal),
      taxAmount: Number(order.tax_amount),
      discountAmount: Number(order.discount_amount),
      totalAmount: Number(order.total_amount),
      paymentMethod: order.payment_method,
      paymentStatus: order.payment_status,
      status: order.status,
      notes: order.notes,
      createdAt: order.created_at,
      createdBy: String(order.created_by),
      items: insertedItems.map((i) => ({
        id: String(i.id),
        productId: String(i.product_id),
        quantity: i.quantity,
        unitPrice: Number(i.unit_price),
        totalPrice: Number(i.total_price),
      })),
    };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

export const getOrderById = async ({ id, requester }) => {
  const { rows: orderRows } = await pool.query(
    `SELECT id, order_number, customer_name, customer_email, customer_phone,
            subtotal, tax_amount, discount_amount, total_amount,
            payment_method, payment_status, status, notes, created_at, created_by
     FROM orders
     WHERE id = $1`,
    [id]
  );

  const order = orderRows[0];
  if (!order) return null;

  if (requester.role !== 'ADMIN' && String(order.created_by) !== String(requester.id)) {
    const err = new Error('You do not have permission to view this order');
    err.statusCode = 403;
    throw err;
  }

  const { rows: itemRows } = await pool.query(
    `SELECT oi.id,
            oi.product_id,
            p.name AS product_name,
            oi.quantity,
            oi.unit_price,
            oi.total_price
     FROM order_items oi
     JOIN products p ON p.id = oi.product_id
     WHERE oi.order_id = $1
     ORDER BY oi.id ASC`,
    [order.id]
  );

  return {
    id: String(order.id),
    orderNumber: order.order_number,
    customerName: order.customer_name,
    customerEmail: order.customer_email,
    customerPhone: order.customer_phone,
    subtotal: Number(order.subtotal),
    taxAmount: Number(order.tax_amount),
    discountAmount: Number(order.discount_amount),
    totalAmount: Number(order.total_amount),
    paymentMethod: order.payment_method,
    paymentStatus: order.payment_status,
    status: order.status,
    notes: order.notes,
    createdAt: order.created_at,
    createdBy: String(order.created_by),
    items: itemRows.map((i) => ({
      id: String(i.id),
      productId: String(i.product_id),
      productName: i.product_name,
      quantity: i.quantity,
      unitPrice: Number(i.unit_price),
      totalPrice: Number(i.total_price),
    })),
  };
};
