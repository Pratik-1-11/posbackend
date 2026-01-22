
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function listPolicies() {
    console.log('Listing all RLS policies for products table...');
    const { data, error } = await supabase.rpc('get_table_policies', { table_name: 'products' });

    // If the RPC doesn't exist, we can try to query pg_policies directly if we have permission
    if (error) {
        console.log('RPC failed, trying direct query if possible...');
        const { data: policies, error: polError } = await supabase
            .from('pg_policies')
            .select('*')
            .eq('tablename', 'products');

        if (polError) {
            // Last resort: run a query that we know is RLS-enabled and see what happens
            console.error('Could not list policies directly. Please check Supabase dashboard.');
        } else {
            console.log('Policies found:', policies);
        }
    } else {
        console.log('Policies found:', data);
    }
}

// Alternatively, let's just run a raw query via a temporary function if possible
async function listPoliciesRaw() {
    const { data, error } = await supabase.from('pg_policies').select('*').eq('tablename', 'products');
    if (error) {
        // Try another way to get info
        const { data: dbInfo, error: dbError } = await supabase
            .from('profiles')
            .select('count')
            .limit(1);
        console.log('Can connect to DB. Profiles check:', dbInfo);
    } else {
        console.log('Policies:', data);
    }
}

listPoliciesRaw();
