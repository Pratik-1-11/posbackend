import express from 'express';
import {
    getIntegrations,
    createIntegration,
    getWebhooks,
    createWebhook,
    triggerSync,
    getSyncJobs
} from '../controllers/integration.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = express.Router();

router.use(requireTenantAuth);

// Integrations
router.get('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), getIntegrations);
router.post('/', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), createIntegration);

// Webhooks
router.get('/webhooks', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), getWebhooks);
router.post('/webhooks', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), createWebhook);

// Sync Jobs
router.get('/sync', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), getSyncJobs);
router.post('/sync/trigger', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), triggerSync);

export default router;
