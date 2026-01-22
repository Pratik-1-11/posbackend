
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testKey() {
    console.log('Testing Service Role Key...');
    const { data: users, error } = await supabase.auth.admin.listUsers();

    if (error) {
        console.error('Key test failed! This is likely NOT a service role key:', error.message);
    } else {
        console.log('Key test successful! Service role confirmed. User count:', users.users.length);
    }
}

testKey();
