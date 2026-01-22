import { Router } from 'express';
import { list, getOne, create, update, remove, adjustStock, listCategories } from '../controllers/product.controller.js';

import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';
import { validate } from '../middleware/validate.middleware.js';
import { createProductSchema, updateProductSchema } from '../utils/validators/product.schemas.js';
import { upload } from '../utils/upload.service.js';

const router = Router();

router.use(requireAuth);
router.use(resolveTenant);

router.get('/categories', listCategories);
router.get('/', list);
router.get('/:id', getOne);

router.post('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'CASHIER', 'cashier'), upload.single('image'), validate(createProductSchema), create);
router.put('/:id', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'CASHIER', 'cashier'), upload.single('image'), validate(updateProductSchema), update);
router.post('/:id/adjust', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'CASHIER', 'cashier'), adjustStock);
router.delete('/:id', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), remove);



export default router;
