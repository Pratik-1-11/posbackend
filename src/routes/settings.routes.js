import { Router } from 'express';
import { getSettings, updateSettings } from '../controllers/settings.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireTenantAuth);

router.get('/', getSettings);
router.put('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), updateSettings);


export default router;
