
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load env vars
dotenv.config({ path: path.join(__dirname, '.env') });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkUsers() {
    const { data: profiles, error } = await supabase
        .from('profiles')
        .select('email, role');

    if (error) {
        console.error('Error:', error.message);
    } else {
        profiles.forEach(p => {
            console.log(`${p.email}|${p.role}`);
        });
    }
}

checkUsers();
