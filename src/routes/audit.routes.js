import { Router } from 'express';
import { list } from '../controllers/audit.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireTenantAuth);

// Only Admins and Managers should see audit logs
router.get('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), list);

export default router;
