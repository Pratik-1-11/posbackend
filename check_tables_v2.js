
import supabase from './src/config/supabase.js';

async function checkSpecificTables() {
    try {
        const { error: error1 } = await supabase.from('stock_movements').select('*').limit(1);
        console.log('stock_movements exists:', !error1);
        if (error1) console.log('stock_movements error:', error1.message);

        const { error: error2 } = await supabase.from('inventory_movements').select('*').limit(1);
        console.log('inventory_movements exists:', !error2);
        if (error2) console.log('inventory_movements error:', error2.message);
    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkSpecificTables();
