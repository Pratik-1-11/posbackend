import { Router } from 'express';
import { list, create, update, remove } from '../controllers/purchase.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireTenantAuth);

router.get('/', list);
router.post('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), create);
router.route('/:id')
    .put(requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), update)
    .delete(requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), remove);


export default router;
