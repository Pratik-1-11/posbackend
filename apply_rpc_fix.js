import 'dotenv/config';
import pg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const runMigration = async () => {
    let connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
        const { DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, DB_NAME } = process.env;
        if (DB_USER && DB_PASSWORD && DB_HOST) {
            connectionString = `postgresql://${DB_USER}:${encodeURIComponent(DB_PASSWORD)}@${DB_HOST}:${DB_PORT || 5432}/${DB_NAME || 'postgres'}?sslmode=require`;
        } else {
            console.error('Database configuration missing in .env');
            return;
        }
    }

    const client = new pg.Client({
        connectionString,
        ssl: { rejectUnauthorized: false }
    });

    try {
        await client.connect();
        console.log('Connected to database');

        const sqlPath = path.join(__dirname, 'supabase', 'migrations', '026_secure_pos_sale_v2.sql');
        const sql = fs.readFileSync(sqlPath, 'utf8');

        console.log('Applying migration 026...');
        await client.query(sql);
        console.log('✅ Migration 026 applied successfully');

    } catch (err) {
        console.error('❌ Migration failed:', err);
    } finally {
        await client.end();
    }
};

runMigration();
