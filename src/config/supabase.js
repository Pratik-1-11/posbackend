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
// Standard Supabase anon keys often contains 'anon' in their JWT payload or the user might have named it so.
// We check if it matches the actual anon key variable if provided.
if (process.env.SUPABASE_ANON_KEY && supabaseKey === process.env.SUPABASE_ANON_KEY) {
    console.error('🚨 CRITICAL ERROR: SUPABASE_SERVICE_ROLE_KEY is identical to SUPABASE_ANON_KEY');
    console.error('   Backend MUST use SERVICE_ROLE_KEY for admin operations');
    process.exit(1);
}

// Fallback hint if the key definitely looks like a public key
if (supabaseKey.toLowerCase().includes('anon') && supabaseKey.length < 150) {
    console.warn('⚠️ WARNING: Your SUPABASE_SERVICE_ROLE_KEY contains "anon" and is short.');
    console.warn('   Please ensure you are using the Service Role Key, not the Anon/Public key.');
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
