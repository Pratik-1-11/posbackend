import { Router } from 'express';
import { list, getOne, create, update, getTransactions, addTransaction, getHistory, getAgingReport } from '../controllers/customer.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';

const router = Router();

router.use(requireAuth);
router.use(resolveTenant);

router.get('/aging', getAgingReport);

router.route('/')
    .get(list)
    .post(create);

router.route('/:id')
    .get(getOne)
    .put(update);

router.route('/:id/transactions')
    .get(getTransactions)
    .post(addTransaction);

router.route('/:id/history')
    .get(getHistory);

export default router;
