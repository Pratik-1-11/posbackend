
import supabase from './src/config/supabase.js';

async function testRLS() {
    console.log('Testing Backend Client RLS Bypass...');
    const { data, error, count } = await supabase
        .from('profiles')
        .select('*', { count: 'exact', head: true });

    if (error) {
        console.error('❌ Backend Client Failed to query profiles:', error.message, error.code);
    } else {
        console.log(`✅ Backend Client Success! Found ${count} profiles.`);
    }
}

testRLS();
