import { Router } from 'express';
import { createReturn, listReturns, getReturn } from '../controllers/return.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.post('/', requireTenantAuth, createReturn);
router.get('/', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'admin', 'manager', 'cashier'), listReturns);
router.get('/:id', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'admin', 'manager', 'cashier'), getReturn);

export default router;
