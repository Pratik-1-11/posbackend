
import supabase from './src/config/supabase.js';

async function checkResourcesDetailed() {
    try {
        const { data: profile, error: err0 } = await supabase
            .from('profiles')
            .select('*')
            .eq('email', 'mydreammart@gmail.com')
            .single();
        console.log('Profile branch_id:', profile?.branch_id, 'type:', typeof profile?.branch_id);

        const { error: err1 } = await supabase.from('vw_return_items_detail').select('*').limit(1);
        console.log('vw_return_items_detail exists:', !err1, err1?.message || '');

    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkResourcesDetailed();
