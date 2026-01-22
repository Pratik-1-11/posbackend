import Joi from '@hapi/joi';

export const createOrderSchema = Joi.object({
  customerName: Joi.string().allow('', null).max(100),
  customerEmail: Joi.string().email().allow('', null).max(100),
  customerPhone: Joi.string().allow('', null).max(20),
  discountAmount: Joi.number().precision(2).min(0).default(0),
  taxAmount: Joi.number().precision(2).min(0).default(0),
  paymentMethod: Joi.string().valid('cash', 'card', 'qr', 'mixed', 'credit').required(),
  paymentDetails: Joi.object().pattern(Joi.string(), Joi.number()).optional(),
  notes: Joi.string().allow('', null),
  items: Joi.array()
    .items(
      Joi.object({
        productId: Joi.string().guid({ version: 'uuidv4' }).required(),
        quantity: Joi.number().integer().min(1).required(),
      })
    )
    .min(1)
    .required(),
  customerId: Joi.string().guid({ version: 'uuidv4' }).allow(null, '').optional(),
});
