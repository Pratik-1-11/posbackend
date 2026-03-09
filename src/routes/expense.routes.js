import { Router } from 'express';
import { list, create, update, remove } from '../controllers/expense.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireTenantAuth);

router.get('/', list);
router.post('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), create);
router.route('/:id')
    .put(requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), update)
    .delete(requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), remove);


export default router;
