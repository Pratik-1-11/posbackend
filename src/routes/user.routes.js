import { Router } from 'express';
import { getUsers, createUser, updateUser, deleteUser } from '../controllers/user.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
import { resolveTenant } from '../middleware/tenantResolver.js';
import { requireRole } from '../middleware/role.middleware.js';


const router = Router();

// All user routes require Auth, Tenant Context, and ADMIN role
router.use(requireAuth);
router.use(resolveTenant);
router.use(requireRole('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'));


router.get('/', getUsers);
router.post('/', createUser);
router.patch('/:id', updateUser);
router.delete('/:id', deleteUser);

export default router;
