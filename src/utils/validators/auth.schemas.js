import Joi from '@hapi/joi';

export const loginSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().min(6).required(),
});

export const registerSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().min(6).required(),
  full_name: Joi.string().min(1).max(100).required(),
  role: Joi.string().valid('super_admin', 'branch_admin', 'cashier', 'inventory_manager').default('cashier'),
  branch_id: Joi.string().guid({ version: 'uuidv4' }).allow(null, ''),
});
