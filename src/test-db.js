import pg from 'pg';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '../.env') });

const { Pool } = pg;
const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME || 'pos_db',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
});

async function test() {
    try {
        console.log('Testing connection to:', process.env.DB_HOST, process.env.DB_NAME);
        const client = await pool.connect();
        console.log('Connected successfully!');
        const res = await client.query('SELECT NOW()');
        console.log('Result:', res.rows[0]);
        client.release();
    } catch (err) {
        console.error('CONNECTION ERROR FULL DETAILS:');
        console.error(err);
        if (err.errors) {
            console.error('Aggregate errors:');
            err.errors.forEach((e, i) => console.error(`Error ${i}:`, e));
        }
    } finally {
        await pool.end();
    }
}

test();
