import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from .env file
dotenv.config({
  path: path.join(__dirname, '../../.env')
});

const env = process.env.NODE_ENV || 'development';

export const config = {
  // Server configuration
  nodeEnv: env,
  port: parseInt(process.env.PORT || '5000', 10),

  // Database configuration
  db: {
    connectionString: process.env.DATABASE_URL || undefined,
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'pos_db',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || '',
    ssl: process.env.DB_SSL === 'true' || process.env.DB_SSL === '1'
      ? { rejectUnauthorized: false }
      : false,
  },

  // JWT configuration
  jwt: {
    secret: process.env.JWT_SECRET || (env === 'production' ? '' : 'dev_jwt_secret_change_me'),
    expiresIn: process.env.JWT_EXPIRES_IN || '1d',
  },

  // Security
  // ============================================================================
  // CRITICAL SECURITY: CORS Origin Validation (Fix #12)
  // ============================================================================
  cors: {
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, Postman, same-origin)
      if (!origin) {
        console.log('[CORS] Internal/Non-browser request (no origin)');
        return callback(null, true);
      }

      // Whitelist of allowed origins
      const allowedOrigins = [
        process.env.CORS_ORIGIN, // From .env
        process.env.NODE_ENV === 'development' && 'http://localhost:5173',
        process.env.NODE_ENV === 'development' && 'http://localhost:5174',
        process.env.NODE_ENV === 'development' && 'http://127.0.0.1:5173',
      ].filter(Boolean);

      console.log(`[CORS] Request from: ${origin}`);
      console.log(`[CORS] Allowed: ${JSON.stringify(allowedOrigins)}`);

      if (allowedOrigins.includes(origin) || allowedOrigins.some(ao => origin.startsWith(ao))) {
        console.log('[CORS] Origin allowed');
        callback(null, true);
      } else {
        console.warn('[CORS] Blocked request from unauthorized origin:', origin);
        callback(new Error(`Not allowed by CORS policy. Origin: ${origin}`));
      }
    },
    credentials: true
  },

  // Rate limiting
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '900000', 10), // 15 minutes
    max: parseInt(process.env.RATE_LIMIT_MAX || '1000', 10), // Limit each IP to 1000 requests per windowMs
  },

  // Roles
  roles: {
    SUPER_ADMIN: 'super_admin',
    BRANCH_ADMIN: 'branch_admin',
    CASHIER: 'cashier',
    INVENTORY_MANAGER: 'inventory_manager',
  },
};

// Validate required environment variables
const requiredEnvVars = ['JWT_SECRET'];

if (env === 'production') {
  const missingVars = requiredEnvVars.filter((key) => !process.env[key]);
  if (missingVars.length > 0) {
    console.error(`🚨 CRITICAL ERROR: Missing required environment variables: ${missingVars.join(', ')}`);
    console.error('   Please set these in your hosting platform (Railway/Render/etc.)');
    process.exit(1);
  }
}
