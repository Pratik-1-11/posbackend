
import supabase from './src/config/supabase.js';

async function checkResourcesFinal() {
    try {
        console.log('Checking RPCs and Tables...');

        // 1. Check if adjust_branch_stock works (calling with dummy data that might fail but show info)
        const { error: err1 } = await supabase.rpc('adjust_branch_stock', {
            p_tenant_id: '00000000-0000-0000-0000-000000000000',
            p_branch_id: '00000000-0000-0000-0000-000000000000',
            p_product_id: '00000000-0000-0000-0000-000000000000',
            p_user_id: '00000000-0000-0000-0000-000000000000',
            p_quantity: 0,
            p_type: 'adjustment',
            p_reason: 'Test'
        });

        if (err1) {
            console.log('adjust_branch_stock error:', err1.message);
            // If it still says inventory_movements doesn't exist, we know it hasn't been updated
        } else {
            console.log('adjust_branch_stock called (likely valid).');
        }

        // 2. Check stock_movements columns
        const { data: cols, error: err2 } = await supabase
            .from('stock_movements')
            .select('*')
            .limit(1);

        if (err2) {
            console.log('stock_movements error:', err2.message);
        } else {
            console.log('stock_movements columns found:', Object.keys(cols[0] || {}));
        }

    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkResourcesFinal();
