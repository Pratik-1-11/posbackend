import { Router } from 'express';
import {
    getDailySales,
    getCashierStats,
    getStockSummary,
    getExpenseSummary,
    getPurchaseSummary,
    getProductPerformance,
    getHealthOverview,
    getPerformanceAnalytics,
    getVatReport,
    getDashboardSummary
} from '../controllers/report.controller.js';

import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// Reports are generally for admins
router.get('/daily', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getDailySales);
router.get('/health', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getHealthOverview);
router.get('/performance', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getPerformanceAnalytics);
router.get('/cashier', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getCashierStats);
router.get('/vat', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getVatReport);
router.get('/summary', requireAuth, resolveTenant, getDashboardSummary);


router.get('/stock', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER', 'admin', 'manager'), getStockSummary);
router.get('/expenses', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getExpenseSummary);
router.get('/purchases', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getPurchaseSummary);
router.get('/products', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'admin', 'manager'), getProductPerformance);


export default router;
