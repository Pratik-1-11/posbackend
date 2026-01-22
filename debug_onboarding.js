
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testOnboarding() {
    const timestamp = Date.now();
    const name = `Test Tenant ${timestamp}`;
    const slug = `test-${timestamp}`;
    const email = `admin_${timestamp}@test.com`;

    console.log('1. Creating Tenant...');
    const { data: tenant, error: tenantError } = await supabase
        .from('tenants')
        .insert({
            name,
            slug,
            contact_email: email,
            subscription_tier: 'basic',
            subscription_status: 'trial',
            is_active: true,
            type: 'vendor'
        })
        .select()
        .single();

    if (tenantError) {
        console.error('Tenant Error:', tenantError);
        return;
    }
    console.log('Tenant Created:', tenant.id);

    console.log('2. Creating Auth User...');
    const { data: authUser, error: authError } = await supabase.auth.admin.createUser({
        email: email,
        password: 'Password123!',
        email_confirm: true,
        user_metadata: {
            full_name: `${name} Admin`,
            role: 'VENDOR_ADMIN',
            tenant_id: tenant.id
        }
    });

    if (authError) {
        console.error('Auth Error:', authError);
        return;
    }
    console.log('Auth User Created:', authUser.user.id);

    console.log('3. Upserting Profile...');
    const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .upsert({
            id: authUser.user.id,
            full_name: `${name} Admin`,
            email: email,
            role: 'VENDOR_ADMIN',
            tenant_id: tenant.id,
            is_active: true
        })
        .select();

    if (profileError) {
        console.error('Profile Error:', profileError);
    } else {
        console.log('Profile Created:', profile);
    }
}

testOnboarding();
