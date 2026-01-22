import 'dotenv/config';
import fs from 'fs';
import pg from 'pg';
const { Pool } = pg;

const databaseUrl = process.env.DATABASE_URL ||
    `postgresql://${process.env.DB_USER}:${encodeURIComponent(process.env.DB_PASSWORD)}@${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`;

if (!databaseUrl || databaseUrl.includes('undefined')) {
    console.error('Error: DATABASE_URL or DB credentials (DB_USER, DB_PASSWORD, etc.) are required in .env');
    process.exit(1);
}

const pool = new Pool({
    connectionString: databaseUrl,
});

async function runSql() {
    const filePath = process.argv[2];
    if (!filePath) {
        console.error('Usage: node src/scripts/run_sql_direct.js <path-to-sql-file>');
        process.exit(1);
    }

    try {
        const sqlContent = fs.readFileSync(filePath, 'utf8');

        console.log(`Executing SQL from ${filePath}...`);
        await pool.query(sqlContent);
        console.log('Successfully executed SQL.');
        await pool.end();

    } catch (err) {
        console.error('Failed to run SQL:', err);
        process.exit(1);
    }
}

runSql();
