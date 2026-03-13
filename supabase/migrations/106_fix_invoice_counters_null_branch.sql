
-- Migration: 106_fix_invoice_counters_null_branch.sql
-- Purpose: Fix 500 error on sales when branch_id is NULL by handling it in sequential numbering.

-- 1. Modify invoice_counters to handle optional branch_id
-- We drop the old PK and create a new one that uses a default UUID for NULL branch_id
DO $$
BEGIN
    -- Drop existing primary key if it exists
    ALTER TABLE public.invoice_counters DROP CONSTRAINT IF EXISTS invoice_counters_pkey;
    
    -- Add a unique constraint that allows null-equivalent UUID
    -- We'll keep branch_id as NULLABLE in the schema but use a COALESCE in logic
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'invoice_counters' AND column_name = 'branch_id') THEN
         -- This shouldn't happen based on 038 but being safe
         ALTER TABLE public.invoice_counters ADD COLUMN branch_id UUID REFERENCES public.branches(id);
    END IF;

    -- Create new Primary Key (tenant_id, branch_id, fiscal_year)
    -- But since we already have branch_id as part of PK, we need to ensure it can be assigned a default.
    -- However, it's safer to just RE-ADD the PK but ensure we COALESCE it in the function.
    -- To allow it in the table with NULL, we can't use it in PK.
    
    -- Better approach: Change PK to use a surrogate ID or just re-define it carefully.
    -- Let's use a unique index for (tenant_id, COALESCE(branch_id, '00000000-0000-0000-0000-000000000000'), fiscal_year)
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
    -- We use COALESCE in the insert and conflict check
    INSERT INTO public.invoice_counters (tenant_id, branch_id, fiscal_year, current_number)
    VALUES (p_tenant_id, v_safe_branch_id, v_fiscal_year, 1)
    ON CONFLICT (tenant_id, branch_id, fiscal_year)
    DO UPDATE SET current_number = public.invoice_counters.current_number + 1
    RETURNING current_number INTO v_next_number;

    RETURN 'INV-' || v_branch_code || '-' || v_fiscal_year || '-' || LPAD(v_next_number::TEXT, 6, '0');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-run sequential PK check (since we might have rows with NULL that previously failed? No, they couldn't exist)
-- Ensure branch_id has a default in the table to allow the PK to work if we don't drop it?
-- Actually, the best fix for PK constraint is:
ALTER TABLE public.invoice_counters ALTER COLUMN branch_id SET DEFAULT '00000000-0000-0000-0000-000000000000';
UPDATE public.invoice_counters SET branch_id = '00000000-0000-0000-0000-000000000000' WHERE branch_id IS NULL;
ALTER TABLE public.invoice_counters ALTER COLUMN branch_id SET NOT NULL;
ALTER TABLE public.invoice_counters ADD CONSTRAINT invoice_counters_pkey_new PRIMARY KEY (tenant_id, branch_id, fiscal_year);
