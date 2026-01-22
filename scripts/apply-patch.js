import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const sql = `
-- Profiles: is_active
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'is_active') THEN
        ALTER TABLE public.profiles ADD COLUMN is_active BOOLEAN DEFAULT TRUE;
    END IF;
END $$;

-- Settings: tenant_id
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'settings' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.settings ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
        UPDATE public.settings SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
    END IF;
END $$;

-- Branches: tenant_id
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'branches' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.branches ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
        UPDATE public.branches SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
    END IF;
END $$;

-- Customer Transactions: tenant_id
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'customer_transactions' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.customer_transactions ADD COLUMN tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
        UPDATE public.customer_transactions SET tenant_id = '00000000-0000-0000-0000-000000000002' WHERE tenant_id IS NULL;
    END IF;
END $$;
`;

async function apply() {
    console.log('Applying schema patch...');
    // Note: Supabase JS client doesn't have a direct 'query' method for raw SQL.
    // We usually have to use an RPC for this, or direct Postgres connection.
    // But I can try to use the 'pg' pool if the user has it configured correctly.
    console.log('Please run the SQL in migrations/013_schema_patch.sql in your Supabase SQL Editor.');
}

apply();
