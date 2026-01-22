import pg from 'pg';
import { config } from './env.js';
import logger from '../utils/logger.js';

const { Pool } = pg;

// Create a new pool instance
const poolConfig = config.db.connectionString
  ? {
      connectionString: config.db.connectionString,
      ssl: config.db.ssl,
      max: 20, // max number of clients in the pool
      idleTimeoutMillis: 30000, // how long a client is allowed to remain idle before being closed
      connectionTimeoutMillis: 2000, // how long to wait when connecting a new client
    }
  : {
      host: config.db.host,
      port: config.db.port,
      database: config.db.database,
      user: config.db.user,
      password: config.db.password,
      ssl: config.db.ssl,
      max: 20, // max number of clients in the pool
      idleTimeoutMillis: 30000, // how long a client is allowed to remain idle before being closed
      connectionTimeoutMillis: 2000, // how long to wait when connecting a new client
    };

const pool = new Pool(poolConfig);

// Test the connection
const connectDB = async () => {
  try {
    const client = await pool.connect();
    if (config.db.connectionString) {
      logger.info('PostgreSQL connected (DATABASE_URL)');
    } else {
      logger.info(`PostgreSQL connected: ${config.db.host}:${config.db.port}/${config.db.database}`);
    }
    client.release();
  } catch (error) {
    const details = error?.detail ? ` | detail: ${error.detail}` : '';
    const code = error?.code ? ` | code: ${error.code}` : '';
    logger.error(`Error connecting to PostgreSQL: ${error?.message || String(error)}${code}${details}`);
    logger.error(
      'Hint: Create backend/.env (copy from .env.example) and ensure Postgres is running / DATABASE_URL is correct.'
    );
    process.exit(1);
  }
};

// Handle pool errors
pool.on('error', (err) => {
  logger.error(`Unexpected error on idle client: ${err.message}`);
  process.exit(-1);
});

// Export the pool and connectDB function
export { pool, connectDB };

// Export a query function for convenience
export const query = (text, params) => pool.query(text, params);
