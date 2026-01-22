import { Router } from 'express';
import { getSettings, updateSettings } from '../controllers/settings.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireAuth);
router.use(resolveTenant);

router.get('/', getSettings);
router.put('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'admin'), updateSettings);


export default router;
