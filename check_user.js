
import supabase from './src/config/supabase.js';

async function checkUser() {
    try {
        const { data, error } = await supabase
            .from('profiles')
            .select('id, email, role, branch_id, tenant_id')
            .eq('email', 'mydreammart@gmail.com')
            .single();

        if (error) {
            console.error('Error fetching profile:', error);
            return;
        }

        console.log('User Profile:', data);
    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkUser();
