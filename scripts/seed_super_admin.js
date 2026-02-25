// ============================================================================
// SEED USERS IN SUPABASE (Super Admin, Vendor Admin, Cashier)
// Run: node backend/scripts/seed_super_admin.js
// ============================================================================
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../.env') });

const supabaseUrl = process.env.SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !serviceRoleKey) {
    console.error('ERROR: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
});

const SUPER_TENANT_ID = '00000000-0000-0000-0000-000000000001';

const usersToCreate = [
    { email: 'superadmin@pos.com', password: 'password123', full_name: 'Super Admin', role: 'SUPER_ADMIN', username: 'superadmin', tenant_id: SUPER_TENANT_ID },
    { email: 'vendor@pos.com', password: 'password123', full_name: 'Vendor Admin', role: 'VENDOR_ADMIN', username: 'vendoradmin', tenant_id: SUPER_TENANT_ID },
    { email: 'cashier@pos.com', password: 'password123', full_name: 'Cashier User', role: 'CASHIER', username: 'cashier', tenant_id: SUPER_TENANT_ID },
];

async function ensureSuperTenantExists() {
    console.log('Ensuring super tenant exists...');
    const { error } = await supabase.from('tenants').upsert(
        { id: SUPER_TENANT_ID, name: 'Platform Admin', slug: 'platform-admin', type: 'super', email: 'admin@platform.com' },
        { onConflict: 'id' }
    );
    if (error) {
        console.log('  WARNING - Tenant upsert: ' + error.message + ' (probably already exists, continuing...)');
    } else {
        console.log('  OK - Super tenant ready');
    }
}

async function getOrCreateAuthUser(userData) {
    const { data: createData, error: createError } = await supabase.auth.admin.createUser({
        email: userData.email,
        password: userData.password,
        email_confirm: true,
    });

    if (!createError) {
        console.log('  OK - New auth user created: ' + createData.user.id);
        return createData.user.id;
    }

    // User already exists - find them
    if (createError.message?.toLowerCase().includes('already') || createError.message?.toLowerCase().includes('exists')) {
        console.log('  INFO - Auth user exists, looking up...');
        const { data: listData, error: listError } = await supabase.auth.admin.listUsers({ perPage: 1000 });
        if (listError) throw new Error('Could not list users: ' + listError.message);

        const existing = listData.users.find(u => u.email === userData.email);
        if (!existing) throw new Error('Could not find existing user: ' + userData.email);

        console.log('  OK - Found existing user: ' + existing.id);

        // Reset password
        const { error: updateError } = await supabase.auth.admin.updateUserById(existing.id, {
            password: userData.password,
            email_confirm: true,
        });
        if (updateError) console.log('  WARNING - Password update: ' + updateError.message);
        else console.log('  OK - Password reset to: ' + userData.password);

        return existing.id;
    }

    throw new Error('Auth creation failed: ' + createError.message);
}

async function seedUsers() {
    console.log('=== POS USER SEEDER ===\n');

    await ensureSuperTenantExists();
    console.log('');

    for (const userData of usersToCreate) {
        console.log('Processing: ' + userData.email + ' (' + userData.role + ')');
        try {
            const userId = await getOrCreateAuthUser(userData);

            const { error: profileError } = await supabase
                .from('profiles')
                .upsert(
                    { id: userId, email: userData.email, full_name: userData.full_name, role: userData.role, username: userData.username, tenant_id: userData.tenant_id },
                    { onConflict: 'id' }
                );

            if (profileError) {
                console.log('  ERROR - Profile upsert: ' + profileError.message);
            } else {
                console.log('  OK - Profile set: role=' + userData.role);
            }
        } catch (err) {
            console.log('  ERROR: ' + err.message);
        }
        console.log('');
    }

    console.log('');
    console.log('=== LOGIN CREDENTIALS ===');
    console.log('Super Admin:  superadmin@pos.com / password123');
    console.log('Vendor Admin: vendor@pos.com     / password123');
    console.log('Cashier:      cashier@pos.com    / password123');
    console.log('=========================');
}

seedUsers().catch(err => {
    console.error('FATAL: ' + err.message);
    process.exit(1);
});
