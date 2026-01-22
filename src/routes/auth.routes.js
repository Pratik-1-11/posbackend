import { Router } from 'express';

import { login, register, logout, getCurrentUser } from '../controllers/auth.controller.js';
import { requireAuth } from '../middleware/auth.middleware.js';
// import { requireRole } from '../middleware/role.middleware.js';
import { validate } from '../middleware/validate.middleware.js';
import { loginSchema, registerSchema } from '../utils/validators/auth.schemas.js';

const router = Router();

router.post('/login', validate(loginSchema), login);
// Allow public registration for MVP setup ease. In prod, this should be protected.
router.post('/register', validate(registerSchema), register);
router.post('/logout', requireAuth, logout);
router.get('/me', requireAuth, getCurrentUser);

export default router;
