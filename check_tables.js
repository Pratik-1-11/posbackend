
import supabase from './src/config/supabase.js';

async function checkTables() {
    try {
        const { data, error } = await supabase
            .from('information_schema.tables')
            .select('table_name')
            .eq('table_schema', 'public');

        if (error) {
            console.error('Error fetching tables:', error);
            return;
        }

        console.log('Tables in public schema:');
        data.forEach(t => console.log(`- ${t.table_name}`));
    } catch (err) {
        console.error('Unexpected error:', err);
    }
}

checkTables();
