
import pg from 'pg';
import dotenv from 'dotenv';
const result = dotenv.config();
console.log('Dotenv result:', result.parsed ? 'loaded' : 'failed');

const { Client } = pg;

const client = new Client({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME || 'pos_db',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
});

async function main() {
    console.log(`Connecting to ${process.env.DB_USER}@${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
    try {
        await client.connect();
        console.log('Connected!');
        const res = await client.query('SELECT current_user, current_database()');
        console.log('Result:', res.rows[0]);
    } catch (err) {
        console.error('Connection failed:', err.message);
    } finally {
        await client.end();
    }
}

main();
