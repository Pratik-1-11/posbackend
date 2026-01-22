
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

async function testJoin() {
    console.log('Testing Product Insert with Category Join...');

    // First find a category
    const { data: cats } = await supabase.from('categories').select('id, name').limit(1);
    if (!cats || cats.length === 0) {
        console.error('No categories found to test with.');
        return;
    }

    const testProduct = {
        name: 'Test Join ' + Date.now(),
        tenant_id: '00d8415c-3381-42dd-9669-b14be9d551a1',
        category_id: cats[0].id,
        selling_price: 100,
        cost_price: 50,
        stock_quantity: 10
    };

    const { data, error } = await supabase
        .from('products')
        .insert(testProduct)
        .select('*, categories(name)')
        .single();

    if (error) {
        console.error('Join Insert failed:', error.message);
        console.error('Error details:', error);
    } else {
        console.log('Join Insert successful! Category name:', data.categories.name);
        await supabase.from('products').delete().eq('id', data.id);
    }
}

testJoin();
