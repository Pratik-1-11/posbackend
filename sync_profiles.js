
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function syncProfiles() {
    console.log('Syncing Auth Users with Profiles...');
    const { data: users, error: authError } = await supabase.auth.admin.listUsers();

    if (authError) {
        console.error('Failed to list auth users:', authError);
        return;
    }

    const defaultTenantId = '00000000-0000-0000-0000-000000000002';

    for (const user of users.users) {
        const { data: profile } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .single();

        if (!profile) {
            console.log(`Creating missing profile for ${user.email}...`);
            const role = user.email.includes('admin') ? 'SUPER_ADMIN' : 'CASHIER';
            const tenantId = (role === 'SUPER_ADMIN') ? '00000000-0000-0000-0000-000000000001' : defaultTenantId;

            await supabase.from('profiles').insert({
                id: user.id,
                email: user.email,
                username: user.email.split('@')[0],
                full_name: user.user_metadata?.full_name || user.email.split('@')[0],
                role: role,
                tenant_id: tenantId,
                is_active: true
            });
        }
    }
    console.log('Sync complete.');
}

syncProfiles();
