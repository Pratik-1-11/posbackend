import express from 'express';
import * as adminController from '../controllers/admin.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = express.Router();

// Apply protection to all admin routes
// Only users with SUPER_ADMIN role can access these
router.use(requireAuth);
router.use(requireRole('SUPER_ADMIN'));

/**
 * Tenant Management
 */
router.get('/tenants', adminController.getAllTenants);
router.get('/tenants/:id', adminController.getTenant);
router.post('/tenants', adminController.createTenant);
router.put('/tenants/:id', adminController.updateTenant);
router.delete('/tenants/:id', adminController.deleteTenant);

/**
 * Status Operations
 */
router.post('/tenants/:id/suspend', adminController.suspendTenant);
router.post('/tenants/:id/activate', adminController.activateTenant);

/**
 * Statistics & Monitoring
 */
router.get('/stats/platform', adminController.getPlatformStats);
router.get('/tenants/:id/stats', adminController.getTenantStats);
router.get('/tenants/:id/users', adminController.getTenantUsers);
router.get('/tenants/:id/activity', (req, res, next) => {
    req.query.tenantId = req.params.id;
    return adminController.getActivityLogs(req, res, next);
});
router.get('/activity', adminController.getActivityLogs);

/**
 * Subscription & Data
 */
router.put('/tenants/:id/subscription', adminController.updateSubscription);
router.put('/tenants/:id/limits', adminController.updateTenantLimits);
router.get('/tenants/:id/export', adminController.exportTenantData);

/**
 * Platform Console
 */
router.get('/settings', adminController.getPlatformSettings);
router.put('/settings', adminController.updatePlatformSetting);

export default router;
