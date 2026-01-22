
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function diagnose() {
    const { data: tenant } = await supabase.from('tenants').select('id').eq('id', '00000000-0000-0000-0000-000000000001').single();
    console.log('TenantExists:', !!tenant);

    const { data: profiles } = await supabase.from('profiles').select('*').eq('role', 'SUPER_ADMIN');
    console.log('SuperAdminsCount:', profiles ? profiles.length : 0);

    if (profiles) {
        for (const p of profiles) {
            console.log(`User:${p.email}, TenantId:${p.tenant_id}`);
            const { data, error } = await supabase.from('profiles').select('tenants!inner(name)').eq('id', p.id).single();
            if (error) console.log('ResolveTenantError:', error.message);
            else console.log('ResolveTenantSuccess:', data.tenants.name);
        }
    }
}

diagnose();
