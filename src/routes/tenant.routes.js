import express from 'express';
import * as tenantController from '../controllers/tenant.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = express.Router();

// All tenant routes require authentication
router.use(requireAuth);

/**
 * Subscription & Upgrade Requests
 */
router.get('/subscription', tenantController.getSubscriptionInfo);
router.post('/upgrade-requests', tenantController.requestUpgrade);
router.get('/upgrade-requests', tenantController.getMyUpgradeRequests);

/**
 * Store (Branch) Management
 */
router.get('/branches', tenantController.getBranches);
router.post('/branches', requireRole(['VENDOR_ADMIN', 'ADMIN']), tenantController.createBranch);
router.put('/branches/:id', requireRole(['VENDOR_ADMIN', 'ADMIN']), tenantController.updateBranch);

export default router;
