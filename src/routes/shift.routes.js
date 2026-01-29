import { Router } from 'express';
import {
    getCurrentShift,
    openShift,
    closeShift,
    getShiftSummary
} from '../controllers/shift.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// All shift routes require tenant authentication
router.use(requireTenantAuth);

/**
 * GET /api/shifts/current
 * Check for active shift
 */
router.get('/current', getCurrentShift);

/**
 * POST /api/shifts/open
 * Open a new shift session
 */
router.post('/open', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), openShift);

/**
 * POST /api/shifts/:id/close
 * Close active shift with reconciliation
 */
router.post('/:id/close', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), closeShift);

/**
 * GET /api/shifts/:id/summary
 * Get shift summary (Z-Report)
 */
router.get('/:id/summary', requireRole('VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), getShiftSummary);

export default router;
