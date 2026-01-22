import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

// ============================================================================
// CRITICAL SECURITY: Strict Credential Validation (Fix #10)
// ============================================================================

// Validate URL
if (!supabaseUrl || supabaseUrl.trim() === '') {
    console.error('🚨 CRITICAL ERROR: SUPABASE_URL is not set in environment variables');
    console.error('   Set this in your .env file or hosting platform');
    process.exit(1);
}

// Validate Service Role Key (STRICT - No fallback)
if (!supabaseKey || supabaseKey.trim() === '') {
    console.error('🚨 CRITICAL ERROR: SUPABASE_SERVICE_ROLE_KEY is not set in environment variables');
    console.error('   This is REQUIRED for backend operations');
    console.error('   Set this in your .env file or hosting platform');
    process.exit(1);
}

// Prevent accidental use of ANON key (security check)
if (supabaseKey.includes('anon')) {
    console.error('🚨 CRITICAL ERROR: You appear to be using SUPABASE_ANON_KEY instead of SERVICE_ROLE_KEY');
    console.error('   Backend MUST use SERVICE_ROLE_KEY for admin operations');
    console.error('   Current key starts with:', supabaseKey.substring(0, 20) + '...');
    process.exit(1);
}

// Validate key format (basic check)
if (supabaseKey.length < 100) {
    console.error('🚨 WARNING: SUPABASE_SERVICE_ROLE_KEY appears to be too short');
    console.error('   Service role keys are typically 200+ characters');
    console.error('   Please verify you are using the correct key');
}

const supabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
    }
});

console.log('✅ [Supabase] Service role client initialized successfully');
console.log(`   URL: ${supabaseUrl}`);
console.log(`   Key: ${supabaseKey.substring(0, 15)}... (${supabaseKey.length} chars)`);

export default supabase;
