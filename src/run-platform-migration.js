import pg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '../.env') });

const { Pool } = pg;

// Supabase Direct Postgres Connection
const pool = new Pool({
    host: 'db.biocayznfcubjwwlymnq.supabase.co',
    port: 5432,
    database: 'postgres',
    user: 'postgres',
    password: process.env.DB_PASSWORD, // Using the password from .env
    ssl: { rejectUnauthorized: false }
});

async function runMigration() {
    const migrationFile = path.join(__dirname, '../supabase/migrations/012_platform_management.sql');
    if (!fs.existsSync(migrationFile)) {
        console.error('Migration file not found:', migrationFile);
        process.exit(1);
    }

    const sql = fs.readFileSync(migrationFile, 'utf8');

    try {
        console.log('Connecting to Supabase DB...');
        const client = await pool.connect();
        console.log('Connected. Running migration 012_platform_management.sql...');

        await client.query('BEGIN');
        await client.query(sql);
        await client.query('COMMIT');

        console.log('Migration completed successfully!');
        client.release();
    } catch (err) {
        console.error('Migration failed:', err.message);
        console.error(err);
    } finally {
        await pool.end();
    }
}

runMigration();
