
import supabase from './src/config/supabase.js';

async function checkResources() {
    try {
        console.log('Checking views and tables...');

        const { error: err1 } = await supabase.from('vw_returns_summary').select('*').limit(1);
        console.log('vw_returns_summary exists:', !err1);
        if (err1) console.log('vw_returns_summary error:', err1.message);

        const { error: err2 } = await supabase.from('vw_return_items_detail').select('*').limit(1);
        console.log('vw_return_items_detail exists:', !err2);
        if (err2) console.log('vw_return_items_detail error:', err2.message);

        const { error: err3 } = await supabase.from('inventory_movements').select('*').limit(1);
        console.log('inventory_movements exists:', !err3);
        if (err3) console.log('inventory_movements error:', err3.message);

        const { error: err4 } = await supabase.from('stock_movements').select('*').limit(1);
        console.log('stock_movements exists:', !err4);
        if (err4) console.log('stock_movements error:', err4.message);

    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkResources();
