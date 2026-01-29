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
    getDashboardSummary,
    getPurchaseBook,
    getProfitAnalysis
} from '../controllers/report.controller.js';

import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// Reports are generally for managers and admins
router.get('/daily', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getDailySales);
router.get('/health', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getHealthOverview);
router.get('/performance', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getPerformanceAnalytics);
router.get('/cashier', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getCashierStats);
router.get('/vat', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getVatReport);
router.get('/profit', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getProfitAnalysis);
router.get('/purchase-book', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getPurchaseBook);
router.get('/summary', requireAuth, resolveTenant, getDashboardSummary);


router.get('/stock', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), getStockSummary);
router.get('/expenses', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getExpenseSummary);
router.get('/purchases', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getPurchaseSummary);
router.get('/products', requireAuth, resolveTenant, requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getProductPerformance);


export default router;
