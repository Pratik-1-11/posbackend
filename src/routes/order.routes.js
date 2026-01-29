import { Router } from 'express';

import { create, getOne, list } from '../controllers/order.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.post('/', requireTenantAuth, create);
router.get('/', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), list);
router.get('/:id', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), getOne);

export default router;
