
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testCategories() {
    console.log('Testing Categories Access...');
    const { data, error } = await supabase.from('categories').select('*').limit(1);

    if (error) {
        console.error('Categories read failed:', error.message);
    } else {
        console.log('Categories read successful! Row found:', !!data[0]);
    }

    const { error: insertError } = await supabase.from('categories').insert({
        name: 'Test Cat ' + Date.now(),
        tenant_id: '00d8415c-3381-42dd-9669-b14be9d551a1'
    });

    if (insertError) {
        console.error('Categories insert failed:', insertError.message);
    } else {
        console.log('Categories insert successful!');
    }
}

testCategories();
