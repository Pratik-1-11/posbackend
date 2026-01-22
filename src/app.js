import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import rateLimit from 'express-rate-limit';

import { config } from './config/env.js';
import logger from './utils/logger.js';

import { errorHandler, notFound } from './middleware/error.middleware.js';

import authRoutes from './routes/auth.routes.js';
import userRoutes from './routes/user.routes.js';
import productRoutes from './routes/product.routes.js';
import orderRoutes from './routes/order.routes.js';
import reportRoutes from './routes/report.routes.js';
import expenseRoutes from './routes/expense.routes.js';
import purchaseRoutes from './routes/purchase.routes.js';
import customerRoutes from './routes/customer.routes.js';
import settingsRoutes from './routes/settings.routes.js';
import adminRoutes from './routes/admin.routes.js';
import auditRoutes from './routes/audit.routes.js';



const app = express();

// Trust proxy (required for Railway/Vercel/Heroku)
app.set('trust proxy', 1);

// Global request logger for production debugging
app.use((req, res, next) => {
  console.log(`[INCOMING] ${req.method} ${req.originalUrl} | Origin: ${req.get('origin') || 'no-origin'}`);
  next();
});

app.use(helmet());
app.use(
  cors({
    origin: config.cors.origin,
    credentials: true,
  })
);

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

if (config.nodeEnv !== 'production') {
  app.use(morgan('dev'));
}

const limiter = rateLimit({
  windowMs: config.rateLimit.windowMs,
  max: config.rateLimit.max,
  standardHeaders: true,
  legacyHeaders: false,
  message: { status: 'error', message: 'Too many requests, please try again later.' },
});
app.use(limiter);

// ============================================================================
// CRITICAL SECURITY: Strict Rate Limiting (Fix #6)
// ============================================================================

// Strict rate limit for financial operations (prevent DoS and abuse)
const financialLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10, // 10 requests per minute per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    status: 'error',
    message: 'Too many transactions. Please wait before retrying.'
  },
  skipSuccessfulRequests: false,
});

// Auth rate limiting (prevent brute force)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 attempts per 15 min
  skipSuccessfulRequests: true,
  message: {
    status: 'error',
    message: 'Too many login attempts. Try again in 15 minutes.'
  }
});

app.get('/', (req, res) => {
  res.status(200).json({
    message: 'POS API is running',
    environment: config.nodeEnv,
    version: '1.0.0'
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Apply strict rate limiting first
app.use('/api/auth/login', authLimiter);
app.use('/api/orders', financialLimiter);

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/products', productRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/expenses', expenseRoutes);
app.use('/api/purchases', purchaseRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/audit', auditRoutes);


app.use(notFound);
app.use(errorHandler);

export default app;
