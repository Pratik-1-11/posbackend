import { Router } from 'express';
import { 
    createReturn, 
    getReturns, 
    getReturnById,
    updateReturnStatus,
    processExchange,
    getReturnStatistics,
    getReturnPolicies,
    updateReturnPolicy
} from '../controllers/return.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// Create new return
router.post('/', requireTenantAuth, createReturn);

// Get returns list with filtering
router.get('/', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), getReturns);

// Get return statistics
router.get('/statistics', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getReturnStatistics);

// Get return policies
router.get('/policies', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getReturnPolicies);

// Get single return details
router.get('/:id', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), getReturnById);

// Update return status (manager/admin only)
router.patch('/:id/status', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), updateReturnStatus);

// Process exchange (manager/admin only)
router.post('/:id/exchange', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), processExchange);

// Update return policy (admin only)
router.patch('/policies/:id', requireTenantAuth, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN'), updateReturnPolicy);

export default router;
