
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function checkUser() {
    console.log('--- DIAGNOSTIC: superadmin@pos.com ---');

    const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('*, tenants(*)')
        .eq('email', 'superadmin@pos.com')
        .single();

    if (profileError) {
        console.error('Profile/Tenant Join Error:', profileError.message);

        // Check profile without join
        const { data: p } = await supabase.from('profiles').select('*').eq('email', 'superadmin@pos.com').single();
        console.log('Profile without join:', p);

        if (p && p.tenant_id) {
            const { data: t } = await supabase.from('tenants').select('*').eq('id', p.tenant_id).single();
            console.log('Tenant for this profile:', t);
        }
    } else {
        console.log('Profile with Tenant:', profile);
    }
}

checkUser();
