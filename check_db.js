
import pg from 'pg';
import dotenv from 'dotenv';
dotenv.config();

const { Pool } = pg;

const pool = new Pool({
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
});

async function checkRLS() {
    console.log('Checking database RLS status...');
    try {
        const client = await pool.connect();

        console.log('--- Table RLS Status ---');
        const rlsRes = await client.query(`
            SELECT tablename, rowsecurity 
            FROM pg_tables 
            WHERE schemaname = 'public' 
            AND tablename IN ('products', 'profiles', 'tenants', 'categories');
        `);
        console.table(rlsRes.rows);

        console.log('--- Policies on Products ---');
        const polRes = await client.query(`
            SELECT * FROM pg_policies WHERE tablename = 'products';
        `);
        console.table(polRes.rows);

        console.log('--- Current User ---');
        const userRes = await client.query('SELECT current_user, session_user;');
        console.table(userRes.rows);

        client.release();
    } catch (err) {
        console.error('Database check failed:', err.message);
    } finally {
        await pool.end();
    }
}

checkRLS();
