import Joi from '@hapi/joi';

export const createProductSchema = Joi.object({
  name: Joi.string().min(1).max(100).required(),
  description: Joi.string().allow('').default(''),
  sku: Joi.string().allow(null, '').max(50),
  barcode: Joi.string().allow(null, '').max(50),
  price: Joi.number().precision(2).min(0).required(),
  costPrice: Joi.number().precision(2).min(0).required(),
  stock: Joi.number().integer().min(0).default(0),
  minQuantity: Joi.number().integer().min(0).default(5),
  category: Joi.string().allow('').max(50).default('Uncategorized'),
  isActive: Joi.boolean().default(true),
  image: Joi.any().optional(),
});

export const updateProductSchema = Joi.object({
  name: Joi.string().min(1).max(100),
  description: Joi.string().allow(''),
  sku: Joi.string().allow(null, '').max(50),
  barcode: Joi.string().allow(null, '').max(50),
  price: Joi.number().precision(2).min(0),
  costPrice: Joi.number().precision(2).min(0),
  stock: Joi.number().integer().min(0),
  minQuantity: Joi.number().integer().min(0),
  category: Joi.string().allow('').max(50),
  isActive: Joi.boolean(),
  image: Joi.any().optional(),
}).min(1);
