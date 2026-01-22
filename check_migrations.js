
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function checkMigrations() {
    console.log('Checking migration status...');
    try {
        const { data, error } = await supabase.from('_migrations').select('*');
        if (error) {
            console.log('No _migrations table found. This project might not use standard migration tracking.');
        } else {
            console.log('Migrations:', data);
        }
    } catch (e) {
        console.log('Error checking migrations.');
    }
}

checkMigrations();
