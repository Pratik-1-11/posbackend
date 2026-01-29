import express from 'express';
import * as managerController from '../controllers/manager.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';

const router = express.Router();

// All manager routes require authentication and tenant context
router.use(requireTenantAuth);

router.post('/verify-pin', managerController.verifyManagerAuth);
router.post('/update-pin', managerController.updateManagerPin);

export default router;
