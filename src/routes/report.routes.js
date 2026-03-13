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
    getProfitAnalysis,
    getCustomerAging,
    getForecasting
} from '../controllers/report.controller.js';

import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// All report routes use unified auth (single DB lookup for auth + tenant)
router.use(requireTenantAuth);

// Reports are generally for managers and admins
router.get('/daily', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER'), getDailySales);
router.get('/health', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getHealthOverview);
router.get('/performance', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getPerformanceAnalytics);
router.get('/cashier', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getCashierStats);
router.get('/vat', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getVatReport);
router.get('/profit', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getProfitAnalysis);
router.get('/purchase-book', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getPurchaseBook);
router.get('/aging', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getCustomerAging);
router.get('/forecast', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getForecasting);
router.get('/summary', getDashboardSummary);

router.get('/stock', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER'), getStockSummary);
router.get('/expenses', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getExpenseSummary);
router.get('/purchases', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getPurchaseSummary);
router.get('/products', requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'), getProductPerformance);


export default router;
