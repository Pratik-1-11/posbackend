
-- Migration: 106_fix_invoice_counters_null_branch.sql
-- Purpose: Fix 500 error on sales when branch_id is NULL by handling it in sequential numbering.
-- Robustness: Self-healing check for table existence and removal of FK constraints to allow Global ID.

-- 1. Ensure Table Exists & Handle Branch ID Nullability
DO $$
BEGIN
    -- Check if table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'invoice_counters') THEN
        CREATE TABLE public.invoice_counters (
            tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
            branch_id UUID DEFAULT '00000000-0000-0000-0000-000000000000',
            fiscal_year TEXT NOT NULL,
            current_number INT NOT NULL DEFAULT 0
        );
    ELSE
        -- Table exists, handle constraint migration
        -- 1. Drop the old PK which depended on branch_id being possibly NULL or different
        ALTER TABLE public.invoice_counters DROP CONSTRAINT IF EXISTS invoice_counters_pkey;
        
        -- 2. Drop the FK constraint to branches to allow our "Global" UUID ('0000...0000')
        -- We search for the FK constraint name. Standard is table_column_fkey
        DECLARE
            v_constraint_name TEXT;
        BEGIN
            SELECT constraint_name INTO v_constraint_name
            FROM information_schema.key_column_usage
            WHERE table_name = 'invoice_counters' 
              AND column_name = 'branch_id' 
              AND table_schema = 'public'
              AND constraint_name LIKE '%fkey%';
            
            IF v_constraint_name IS NOT NULL THEN
                EXECUTE 'ALTER TABLE public.invoice_counters DROP CONSTRAINT ' || v_constraint_name;
            END IF;
        END;

        -- 3. Add/Update branch_id column
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'invoice_counters' AND column_name = 'branch_id') THEN
            ALTER TABLE public.invoice_counters ADD COLUMN branch_id UUID DEFAULT '00000000-0000-0000-0000-000000000000';
        ELSE
            ALTER TABLE public.invoice_counters ALTER COLUMN branch_id SET DEFAULT '00000000-0000-0000-0000-000000000000';
            UPDATE public.invoice_counters SET branch_id = '00000000-0000-0000-0000-000000000000' WHERE branch_id IS NULL;
        END IF;
    END IF;
    
    -- Ensure columns are NOT NULL and add Primary Key
    ALTER TABLE public.invoice_counters ALTER COLUMN branch_id SET NOT NULL;
    
    -- Final PK enforcement
    ALTER TABLE public.invoice_counters DROP CONSTRAINT IF EXISTS invoice_counters_pkey;
    ALTER TABLE public.invoice_counters DROP CONSTRAINT IF EXISTS invoice_counters_pkey_new;
    ALTER TABLE public.invoice_counters ADD PRIMARY KEY (tenant_id, branch_id, fiscal_year);

END $$;

-- 2. Update get_next_invoice_number to be resilient to NULL branch_id
CREATE OR REPLACE FUNCTION public.get_next_invoice_number(p_tenant_id UUID, p_branch_id UUID)
RETURNS TEXT AS $$
DECLARE
    v_fiscal_year TEXT;
    v_next_number INT;
    v_branch_code TEXT;
    v_safe_branch_id UUID;
BEGIN
    v_fiscal_year := to_char(NOW(), 'YYYY');
    v_safe_branch_id := COALESCE(p_branch_id, '00000000-0000-0000-0000-000000000000');

    -- get branch code
    IF p_branch_id IS NOT NULL THEN
        SELECT SUBSTRING(name, 1, 3) INTO v_branch_code FROM public.branches WHERE id = p_branch_id AND tenant_id = p_tenant_id;
    END IF;

    IF v_branch_code IS NULL THEN
        v_branch_code := 'M';
    END IF;

    v_branch_code := UPPER(v_branch_code);

    -- atomic increment with gap-free guarantee under row lock
    INSERT INTO public.invoice_counters (tenant_id, branch_id, fiscal_year, current_number)
    VALUES (p_tenant_id, v_safe_branch_id, v_fiscal_year, 1)
    ON CONFLICT (tenant_id, branch_id, fiscal_year)
    DO UPDATE SET current_number = public.invoice_counters.current_number + 1
    RETURNING current_number INTO v_next_number;

    RETURN 'INV-' || v_branch_code || '-' || v_fiscal_year || '-' || LPAD(v_next_number::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
