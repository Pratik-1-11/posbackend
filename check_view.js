
import supabase from './src/config/supabase.js';

async function checkView() {
    try {
        const { data, error } = await supabase
            .from('vw_returns_summary')
            .select('*')
            .limit(1);

        if (error) {
            console.error('View Error:', error);
            return;
        }

        console.log('View Schema:', Object.keys(data[0] || {}));
    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkView();
