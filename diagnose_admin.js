
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

if (!supabaseUrl || !supabaseKey) {
    console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);

async function diagnose() {
    console.log('--- Diagnosis Start ---');

    // 1. Check if "Platform Admin" tenant exists
    console.log('1. Checking for Super Admin Tenant (00000000-0000-0000-0000-000000000001)...');
    const { data: tenant, error: tenantError } = await supabase
        .from('tenants')
        .select('*')
        .eq('id', '00000000-0000-0000-0000-000000000001')
        .single();

    if (tenantError) {
        console.error('FAIL: Tenant check failed:', tenantError.message);
    } else if (!tenant) {
        console.error('FAIL: Super Admin Tenant NOT FOUND.');
    } else {
        console.log('PASS: Tenant found:', tenant.name);
    }

    // 2. Check for Super Admin Profile (assuming email is superadmin@pos.com or we search for any SUPER_ADMIN)
    console.log('\n2. Searching for SUPER_ADMIN profile...');
    const { data: profiles, error: profileError } = await supabase
        .from('profiles')
        .select('*')
        .eq('role', 'SUPER_ADMIN');

    if (profileError) {
        console.error('FAIL: Profile search failed:', profileError.message);
    } else if (!profiles || profiles.length === 0) {
        console.error('FAIL: No profile with role SUPER_ADMIN found.');
    } else {
        console.log(`PASS: Found ${profiles.length} SUPER_ADMIN(s).`);

        // 3. Diagnose each Super Admin
        for (const p of profiles) {
            console.log(`\nChecking Super Admin: ${p.email} (ID: ${p.id})`);
            console.log(`- Tenant ID: ${p.tenant_id}`);

            // Try the join query used in resolveTenant
            console.log('- Testing resolveTenant query...');
            try {
                const { data: resolved, error: resolveError } = await supabase
                    .from('profiles')
                    .select(`
                id,
                tenant_id,
                role,
                tenants!inner (
                  id,
                  name
                )
            `)
                    .eq('id', p.id)
                    .single();

                if (resolveError) {
                    console.error('  FAIL: resolveTenant query failed:', resolveError.message);
                    // Hint: expected error if tenant_id is invalid or null
                } else {
                    console.log('  PASS: resolveTenant query successful. Linked tenant:', resolved.tenants.name);
                }
            } catch (err) {
                console.error('  FAIL: Unexpected error in query:', err);
            }
        }
    }

    // 4. Test fetch all tenants (admin controller action)
    console.log('\n3. Testing getAllTenants query...');
    const { data: allTenants, error: allTenantsError } = await supabase
        .from('tenants')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(5);

    if (allTenantsError) {
        console.error('FAIL: getAllTenants query failed:', allTenantsError.message);
    } else {
        console.log(`PASS: getAllTenants query successful. Retrieved ${allTenants.length} tenants.`);
    }

    console.log('--- Diagnosis End ---');
}

diagnose();
