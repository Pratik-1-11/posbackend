import express from 'express';
import * as managerController from '../controllers/manager.controller.js';
import { requireAuth } from '../middleware/auth.js';
import { attachTenant } from '../middleware/tenant.js';

const router = express.Router();

// All manager routes require authentication and tenant context
router.use(requireAuth);
router.use(attachTenant);

router.post('/verify-pin', managerController.verifyManagerAuth);
router.post('/update-pin', managerController.updateManagerPin);

export default router;
