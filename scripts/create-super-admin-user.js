/**
 * Create Super Admin User Script
 * 
 * Usage: node scripts/create-super-admin-user.js
 */

import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
    console.error('❌ Error: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
    process.exit(1);
}

// Initialize Supabase Admin Client
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

const NEW_USER_EMAIL = 'superadmin@pos.com';
const NEW_USER_PASSWORD = 'password123';
const SUPER_TENANT_ID = '00000000-0000-0000-0000-000000000001';

async function createSuperAdmin() {
    console.log(`🚀 Creating Super Admin user: ${NEW_USER_EMAIL}...`);

    try {
        // 1. Create User in Supabase Auth
        const { data: userData, error: createError } = await supabase.auth.admin.createUser({
            email: NEW_USER_EMAIL,
            password: NEW_USER_PASSWORD,
            email_confirm: true,
            user_metadata: {
                full_name: 'Platform Super Admin'
            }
        });

        if (createError) {
            console.error('❌ Error creating user:', createError.message);
            return;
        }

        const userId = userData.user.id;
        console.log(`✅ User created! ID: ${userId}`);

        // 2. Wait a moment for the profile trigger to run (if you have one)
        // Or we can manually upsert the profile to be safe
        console.log('🔄 Assigning Super Admin role...');

        // We use upsert to ensure the profile exists and has the right role
        const { error: updateError } = await supabase
            .from('profiles')
            .upsert({
                id: userId,
                email: NEW_USER_EMAIL,
                full_name: 'Platform Super Admin',
                role: 'SUPER_ADMIN',
                tenant_id: SUPER_TENANT_ID,
                is_active: true,
                created_at: new Date().toISOString(),
                updated_at: new Date().toISOString()
            });

        if (updateError) {
            console.error('❌ Error updating profile:', updateError.message);
            return;
        }

        console.log('\n🎉 SUCCESS! Super Admin created.');
        console.log(`📧 Email: ${NEW_USER_EMAIL}`);
        console.log(`🔑 Password: ${NEW_USER_PASSWORD}`);
        console.log(`👑 Role: SUPER_ADMIN`);
        console.log(`🏢 Tenant: Platform Admin`);

    } catch (err) {
        console.error('❌ Unexpected error:', err);
    }
}

createSuperAdmin();
