
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testInsert() {
    console.log('Testing Product Insert with Service Role Key...');

    const testProduct = {
        name: 'Test Product ' + Date.now(),
        tenant_id: '00d8415c-3381-42dd-9669-b14be9d551a1', // My Dream Mart
        selling_price: 100,
        cost_price: 50,
        stock_quantity: 10
    };

    const { data, error } = await supabase
        .from('products')
        .insert(testProduct)
        .select()
        .single();

    if (error) {
        console.error('Insert failed:', error.message);
        console.error('Error details:', error);
    } else {
        console.log('Insert successful! Product ID:', data.id);
        // Clean up
        await supabase.from('products').delete().eq('id', data.id);
    }
}

testInsert();
