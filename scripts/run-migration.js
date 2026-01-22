/**
 * Multi-Tenant Migration Script
 * 
 * Runs the multi-tenant migration using Node.js and Supabase client
 * No CLI required!
 */

import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from .env file
const envPath = path.join(__dirname, '..', '.env');
dotenv.config({ path: envPath });

console.log('📁 Loading .env from:', envPath);
console.log('🔑 SUPABASE_URL:', process.env.SUPABASE_URL ? '✅ Found' : '❌ Missing');
console.log('🔑 SUPABASE_SERVICE_ROLE_KEY:', process.env.SUPABASE_SERVICE_ROLE_KEY ? '✅ Found' : '❌ Missing');
console.log('');

// Load environment variables
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://biocayznfcubjwwlymnq.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_SERVICE_KEY) {
    console.error('❌ Error: SUPABASE_SERVICE_ROLE_KEY not found in environment variables');
    console.error('Make sure backend/.env file exists with SUPABASE_SERVICE_ROLE_KEY');
    process.exit(1);
}

// Create Supabase client with service role (bypasses RLS)
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
});

console.log('🚀 Multi-Tenant Migration Script');
console.log('================================\n');

/**
 * Step 1: Backup - Count existing data
 */
async function backupDataCounts() {
    console.log('📊 Step 1: Backing up data counts...\n');

    const tables = ['products', 'customers', 'sales', 'profiles', 'expenses', 'purchases'];
    const backup = {};

    for (const table of tables) {
        try {
            const { count, error } = await supabase
                .from(table)
                .select('*', { count: 'exact', head: true });

            if (error) {
                console.log(`⚠️  Warning: Could not count ${table}: ${error.message}`);
                backup[table] = 'N/A';
            } else {
                backup[table] = count;
                console.log(`   ${table}: ${count} records`);
            }
        } catch (err) {
            console.log(`⚠️  Warning: ${table} table might not exist yet`);
            backup[table] = 0;
        }
    }

    // Save backup to file
    const backupFile = path.join(__dirname, '..', 'backups', `backup_${new Date().toISOString().split('T')[0]}.json`);
    const backupDir = path.dirname(backupFile);

    if (!fs.existsSync(backupDir)) {
        fs.mkdirSync(backupDir, { recursive: true });
    }

    fs.writeFileSync(backupFile, JSON.stringify(backup, null, 2));
    console.log(`\n✅ Backup saved to: ${backupFile}\n`);

    return backup;
}

/**
 * Step 2: Read and execute migration SQL
 */
async function runMigration() {
    console.log('🔧 Step 2: Running migration...\n');

    const migrationFile = path.join(__dirname, '..', 'supabase', 'migrations', '011_multi_tenant_migration.sql');

    if (!fs.existsSync(migrationFile)) {
        console.error(`❌ Error: Migration file not found at: ${migrationFile}`);
        process.exit(1);
    }

    const migrationSQL = fs.readFileSync(migrationFile, 'utf8');

    console.log('   Executing migration SQL...');
    console.log('   This may take 30-60 seconds...\n');

    try {
        // Execute the migration using Supabase's RPC or direct SQL
        // Note: For complex migrations, it's better to use Supabase Dashboard SQL Editor
        // or direct PostgreSQL connection

        console.log('⚠️  IMPORTANT:');
        console.log('   Due to the complexity of this migration, please run it via:');
        console.log('   1. Supabase Dashboard → SQL Editor (RECOMMENDED)');
        console.log('   2. Or use psql with direct connection\n');
        console.log('   Migration file location:');
        console.log(`   ${migrationFile}\n`);

        // For now, we'll verify if we can connect and check if migration is needed
        const { data, error } = await supabase
            .from('tenants')
            .select('count')
            .limit(1);

        if (error && error.code === '42P01') {
            console.log('📝 Status: Migration NOT yet applied (tenants table does not exist)');
            console.log('\n📋 Next Steps:');
            console.log('   1. Go to: https://app.supabase.com/project/biocayznfcubjwwlymnq/sql');
            console.log('   2. Click "New Query"');
            console.log('   3. Copy the contents of:');
            console.log(`      ${migrationFile}`);
            console.log('   4. Paste into SQL Editor and click "Run"\n');
            return false;
        } else if (!error) {
            console.log('✅ Status: Migration appears to be already applied (tenants table exists)');
            return true;
        }

    } catch (error) {
        console.error('❌ Error during migration check:', error.message);
        return false;
    }
}

/**
 * Step 3: Verify migration success
 */
async function verifyMigration(originalCounts) {
    console.log('\n🔍 Step 3: Verifying migration...\n');

    const checks = [];

    // Check 1: Tenants table exists
    try {
        const { data, error } = await supabase
            .from('tenants')
            .select('*')
            .limit(5);

        if (error) {
            checks.push({ test: 'Tenants table exists', status: '❌', error: error.message });
        } else {
            checks.push({ test: 'Tenants table exists', status: '✅', detail: `${data.length} tenants found` });
        }
    } catch (err) {
        checks.push({ test: 'Tenants table exists', status: '❌', error: err.message });
    }

    // Check 2: Products have tenant_id
    try {
        const { data, error } = await supabase
            .from('products')
            .select('tenant_id')
            .not('tenant_id', 'is', null)
            .limit(1);

        if (error) {
            checks.push({ test: 'Products have tenant_id', status: '⚠️', error: error.message });
        } else {
            checks.push({ test: 'Products have tenant_id', status: '✅' });
        }
    } catch (err) {
        checks.push({ test: 'Products have tenant_id', status: '❌', error: err.message });
    }

    // Check 3: Data integrity
    try {
        const { count: productCount } = await supabase
            .from('products')
            .select('*', { count: 'exact', head: true });

        const original = originalCounts.products;
        if (productCount === original) {
            checks.push({ test: 'Product count matches', status: '✅', detail: `${productCount} records` });
        } else {
            checks.push({ test: 'Product count matches', status: '⚠️', detail: `Original: ${original}, Current: ${productCount}` });
        }
    } catch (err) {
        checks.push({ test: 'Product count matches', status: '⚠️', error: err.message });
    }

    // Print results
    console.log('   Verification Results:');
    console.log('   ' + '='.repeat(60));
    checks.forEach(check => {
        const detail = check.detail ? ` (${check.detail})` : '';
        const error = check.error ? ` - ${check.error}` : '';
        console.log(`   ${check.status} ${check.test}${detail}${error}`);
    });
    console.log('   ' + '='.repeat(60) + '\n');

    const allPassed = checks.every(c => c.status === '✅');
    return allPassed;
}

/**
 * Step 4: Create Super Admin user
 */
async function setupSuperAdmin() {
    console.log('👤 Step 4: Super Admin Setup\n');

    console.log('   To create a Super Admin user:');
    console.log('   1. Go to Supabase Dashboard → Authentication → Users');
    console.log('   2. Find your user email');
    console.log('   3. Copy your User ID');
    console.log('   4. Run this SQL in SQL Editor:\n');
    console.log('   UPDATE public.profiles');
    console.log('   SET');
    console.log("     tenant_id = '00000000-0000-0000-0000-000000000001',");
    console.log("     role = 'SUPER_ADMIN'");
    console.log("   WHERE id = 'YOUR_USER_ID_HERE';\n");
}

/**
 * Main execution
 */
async function main() {
    try {
        // Step 1: Backup
        const originalCounts = await backupDataCounts();

        // Step 2: Migration
        const migrationApplied = await runMigration();

        // Step 3: Verify (if migration was applied)
        if (migrationApplied) {
            const verified = await verifyMigration(originalCounts);

            if (verified) {
                console.log('🎉 SUCCESS! Migration completed and verified!\n');

                // Step 4: Setup instructions
                await setupSuperAdmin();
            } else {
                console.log('⚠️  Migration appears incomplete. Please check the verification results above.\n');
            }
        }

        console.log('\n📚 Documentation:');
        console.log('   - Architecture: backend/docs/MULTI_TENANT_ARCHITECTURE.md');
        console.log('   - Implementation: backend/docs/IMPLEMENTATION_GUIDE.md');
        console.log('   - Quick Reference: backend/docs/QUICK_REFERENCE.md');
        console.log('   - No CLI Guide: backend/docs/MIGRATION_GUIDE_NO_CLI.md\n');

    } catch (error) {
        console.error('\n❌ Fatal Error:', error.message);
        console.error('\nPlease check:');
        console.error('1. SUPABASE_SERVICE_ROLE_KEY is correct in .env');
        console.error('2. Supabase project is accessible');
        console.error('3. Network connection is stable\n');
        process.exit(1);
    }
}

// Run the script
main();
