import { StatusCodes } from 'http-status-codes';
import { orders, products, nextOrderId } from '../data/staticData.js';

// Create new order
export const create = async (req, res) => {
  try {
    const { items, paymentMethod = 'CASH' } = req.body;
    const userId = req.user.id;

    // Validate items
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Order must contain at least one item'
      });
    }

    // Calculate totals and validate products
    let subtotal = 0;
    const orderItems = [];

    for (const item of items) {
      const product = products.find(p => p.id === item.productId && p.isActive);
      
      if (!product) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: `Product with ID ${item.productId} not found`
        });
      }

      if (product.stock < item.quantity) {
        return res.status(StatusCodes.BAD_REQUEST).json({
          status: 'error',
          message: `Insufficient stock for ${product.name}. Available: ${product.stock}`
        });
      }

      const itemTotal = product.price * item.quantity;
      subtotal += itemTotal;

      orderItems.push({
        productId: product.id,
        quantity: item.quantity,
        price: product.price
      });
    }

    // Calculate tax and total (assuming 10% tax)
    const tax = subtotal * 0.1;
    const total = subtotal + tax;

    const newOrder = {
      id: orders.length + 1,
      userId,
      items: orderItems,
      subtotal: parseFloat(subtotal.toFixed(2)),
      tax: parseFloat(tax.toFixed(2)),
      total: parseFloat(total.toFixed(2)),
      status: 'COMPLETED',
      paymentMethod,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // For static data, we'll just return success without actually modifying the array
    res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: {
        order: newOrder
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to create order'
    });
  }
};

// Get single order
export const getOne = async (req, res) => {
  try {
    const { id } = req.params;
    
    const order = orders.find(o => o.id === parseInt(id));
    
    if (!order) {
      return res.status(StatusCodes.NOT_FOUND).json({
        status: 'error',
        message: 'Order not found'
      });
    }

    // Add product details to order items
    const orderWithProducts = {
      ...order,
      items: order.items.map(item => {
        const product = products.find(p => p.id === item.productId);
        return {
          ...item,
          product: product ? {
            id: product.id,
            name: product.name,
            sku: product.sku
          } : null
        };
      })
    };

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        order: orderWithProducts
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to fetch order'
    });
  }
};
