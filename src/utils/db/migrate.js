import { readFile } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { pool } from '../../config/db.js';
import logger from '../logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Read SQL migration files
const readMigrationFile = async (filename) => {
  try {
    const filePath = path.join(__dirname, 'migrations', filename);
    return await readFile(filePath, 'utf8');
  } catch (error) {
    logger.error(`Error reading migration file ${filename}:`, error);
    process.exit(1);
  }
};

// Create migrations table if it doesn't exist
const createMigrationsTable = async () => {
  const queryText = `
    CREATE TABLE IF NOT EXISTS migrations (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL UNIQUE,
      executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
    );
  `;
  await pool.query(queryText);
};

// Get list of executed migrations
const getExecutedMigrations = async () => {
  const { rows } = await pool.query('SELECT name FROM migrations ORDER BY name');
  return new Set(rows.map(row => row.name));
};

// Execute a single migration
const executeMigration = async (client, migrationName, migrationSQL) => {
  try {
    await client.query('BEGIN');
    await client.query(migrationSQL);
    await client.query('INSERT INTO migrations (name) VALUES ($1)', [migrationName]);
    await client.query('COMMIT');
    logger.info(`Applied migration: ${migrationName}`);
  } catch (error) {
    await client.query('ROLLBACK');
    logger.error(`Error applying migration ${migrationName}:`, error);
    throw error;
  }
};

// Main migration function
const runMigrations = async () => {
  let client;

  try {
    client = await pool.connect();
    await createMigrationsTable();
    const executedMigrations = await getExecutedMigrations();

    // List of migrations in order
    const migrations = [
      '001_initial_schema.sql',
      '002_seed_initial_data.sql',
      '003_add_expenses_purchases.sql',
      '004_add_customers_credit.sql',
      '005_advanced_payment_system.sql',
      '006_expand_profiles_roles.sql',
      '009_create_tenants.sql',
      '010_add_tenant_columns.sql',
      '011_multi_tenant_PART1_schema.sql',
      '012_platform_management.sql',
      '013_stock_movements.sql',
      '014_subscription_management.sql'
    ];


    for (const migration of migrations) {
      if (!executedMigrations.has(migration)) {
        logger.info(`Running migration: ${migration}`);
        const sql = await readMigrationFile(migration);
        await executeMigration(client, migration, sql);
      }
    }

    logger.info('Database migrations completed successfully');
  } catch (error) {
    logger.error('Migration failed:', error);
    process.exit(1);
  } finally {
    if (client) client.release();
    await pool.end();
  }
};

runMigrations();
