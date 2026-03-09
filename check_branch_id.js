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

async function check() {
    try {
        const client = await pool.connect();
        const res = await client.query(`
            SELECT table_name 
            FROM information_schema.columns 
            WHERE column_name = 'branch_id'
            AND table_schema = 'public';
        `);
        console.log('Tables with branch_id:');
        console.table(res.rows);
        client.release();
    } catch (e) {
        console.error(e);
    } finally {
        pool.end();
    }
}
check();
