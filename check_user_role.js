
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

async function checkUser() {
    console.log('--- Checking User Role ---');
    const { data: profile, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('email', 'superadmin@pos.com')
        .single();

    if (error) {
        console.error('Error fetching profile:', error.message);
    } else if (!profile) {
        console.error('User profile not found for superadmin@pos.com');
    } else {
        console.log('Profile found:');
        console.log('- Role:', profile.role);
        console.log('- Tenant ID:', profile.tenant_id);
    }
}

checkUser();
