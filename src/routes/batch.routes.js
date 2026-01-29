import { Router } from 'express';
import { listBatches, createBatch, getExpiringSoon, updateBatchStatus } from '../controllers/batch.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireAuth);
router.use(resolveTenant);

router.get('/', listBatches);
router.get('/expiring', getExpiringSoon);
router.post('/', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), createBatch);
router.patch('/:id/status', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), updateBatchStatus);

export default router;
