-- ============================================================================
-- Fix: Add missing credit_limit column to customers table
-- Fixes "Could not find the 'credit_limit' column" error
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'customers' 
        AND column_name = 'credit_limit'
    ) THEN
        ALTER TABLE public.customers 
        ADD COLUMN credit_limit NUMERIC(10, 2) DEFAULT 0 CHECK (credit_limit >= 0);
        
        RAISE NOTICE '✅ Added credit_limit column to customers table';
    ELSE
        RAISE NOTICE 'ℹ️ credit_limit column already exists';
    END IF;
END $$;

-- Verify
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'customers' 
        AND column_name = 'credit_limit'
    ) THEN
        RAISE NOTICE '✅ Verification Successful: credit_limit exists';
    ELSE
        RAISE EXCEPTION '❌ Verification Failed: credit_limit still missing';
    END IF;
END $$;
