
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function check() {
    // We try to use a view or just a query that bypasses functions
    const { data, error } = await supabase.rpc('get_current_tenant_id'); // Just to see if rpc works
    console.log('RPC Test (get_current_tenant_id):', data, error);

    // Try to call process_pos_sale with just p_tenant_id and see error
    const { data: d2, error: e2 } = await supabase.rpc('process_pos_sale', { p_tenant_id: '00000000-0000-0000-0000-000000000002' });
    console.log('RPC Test (process_pos_sale):', d2, e2);
}

check();
