import { Router } from 'express';
import { voidSale, trackPrint, getAuditTrail, getVoidedSales } from '../controllers/invoice.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

/**
 * POST /api/invoices/:id/void
 * Void a sale - Manager only
 * Body: { reason, authCode?, managerId? }
 */
router.post(
    '/:id/void',
    requireTenantAuth,
    requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'),
    voidSale
);

/**
 * POST /api/invoices/:id/track-print
 * Track invoice print/reprint
 * No body required
 */
router.post(
    '/:id/track-print',
    requireTenantAuth,
    trackPrint
);

/**
 * GET /api/invoices/:id/audit-trail
 * Get modification audit trail for specific invoice
 * Manager only
 */
router.get(
    '/:id/audit-trail',
    requireTenantAuth,
    requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'),
    getAuditTrail
);

/**
 * GET /api/invoices/audit-trail
 * Get all invoice modifications (global)
 * Manager only
 */
router.get(
    '/audit-trail',
    requireTenantAuth,
    requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'),
    getAuditTrail
);

/**
 * GET /api/invoices/voided
 * Get all voided sales
 * Query: ?startDate=X&endDate=Y&page=1&limit=50
 * Manager only
 */
router.get(
    '/voided',
    requireTenantAuth,
    requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'),
    getVoidedSales
);

export default router;
