import { Router } from 'express';
import { list } from '../controllers/audit.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireAuth);
router.use(resolveTenant);

// Only Admins and Managers should see audit logs
router.get('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), list);

export default router;
