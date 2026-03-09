import { Router } from 'express';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';
import { requireRole } from '../middleware/role.middleware.js';
import * as accountingController from '../controllers/accounting.controller.js';

const router = Router();

// Financial routes are restricted to Admins and Managers
router.use(requireTenantAuth);
router.use(requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'));

router.get('/journals', accountingController.getJournalEntries);
router.get('/accounts', accountingController.getChartOfAccounts);
router.get('/profit-loss', accountingController.getProfitAndLoss);
router.get('/trial-balance', accountingController.getTrialBalance);

export default router;
