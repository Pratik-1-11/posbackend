import { Router } from 'express';
import { listBatches, createBatch, getExpiringSoon, updateBatchStatus } from '../controllers/batch.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.use(requireTenantAuth);

router.get('/', listBatches);
router.get('/expiring', getExpiringSoon);
router.post('/', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), createBatch);
router.patch('/:id/status', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), updateBatchStatus);

export default router;
