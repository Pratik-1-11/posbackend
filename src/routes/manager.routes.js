import express from 'express';
import rateLimit from 'express-rate-limit';
import * as managerController from '../controllers/manager.controller.js';
import { requireTenantAuth } from '../middleware/unifiedAuth.js';

const router = express.Router();

const pinLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10, // limit each IP to 10 requests per windowMs
    message: { status: 'error', message: 'Too many PIN verification attempts. Please try again later.' }
});

// All manager routes require authentication and tenant context
router.use(requireTenantAuth);

router.post('/verify-pin', pinLimiter, managerController.verifyManagerAuth);
router.post('/update-pin', managerController.updateManagerPin);

export default router;
