import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

// ============================================================================
// VALIDATION
// ============================================================================

if (!supabaseUrl || supabaseUrl.trim() === '') {
    console.error('🚨 CRITICAL ERROR: SUPABASE_URL is not set in environment variables');
    process.exit(1);
}

if (!supabaseServiceRoleKey || supabaseServiceRoleKey.trim() === '') {
    console.error('🚨 CRITICAL ERROR: SUPABASE_SERVICE_ROLE_KEY is not set in environment variables');
    process.exit(1);
}

if (!supabaseAnonKey || supabaseAnonKey.trim() === '') {
    console.error('🚨 CRITICAL ERROR: SUPABASE_ANON_KEY is not set in environment variables');
    process.exit(1);
}

// ============================================================================
// CLIENT 1: Auth Client (Anon Key)
// Used for: signInWithPassword, signUp, signOut — returns real user sessions
// ============================================================================
export const supabaseAuth = createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
    }
});

// ============================================================================
// CLIENT 2: Admin Client (Service Role Key)
// Used for: reading/writing DB tables (profiles, tenants, etc.) bypassing RLS
// ============================================================================
export const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
    }
});

console.log('✅ [Supabase] Clients initialized successfully');
console.log(`   URL: ${supabaseUrl}`);
console.log(`   Anon Key: ${supabaseAnonKey.substring(0, 20)}... (${supabaseAnonKey.length} chars)`);
console.log(`   Service Role Key: ${supabaseServiceRoleKey.substring(0, 20)}... (${supabaseServiceRoleKey.length} chars)`);

// Default export = admin client (backward compatibility with other controllers)
export default supabaseAdmin;
