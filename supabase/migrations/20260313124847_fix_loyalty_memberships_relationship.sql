-- Fix relationship issue between customers and loyalty_memberships
-- Add explicit foreign key if missing and ensure proper referencing
-- Ensure customers -> loyalty_memberships as a 1:to-many or 1:to-1 relationship is exposed

-- Check if foreign key exists and is correct
DO $$
BEGIN
    -- Verify the foreign key exists on loyalty_memberships
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
          ON ccu.constraint_name = tc.constraint_name
          AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = 'public'
          AND tc.table_name = 'loyalty_memberships'
          AND kcu.column_name = 'customer_id'
          AND ccu.table_name = 'customers'
          AND ccu.column_name = 'id'
    ) THEN
        -- Add the foreign key constraint explicitly if not found
        ALTER TABLE public.loyalty_memberships
        ADD CONSTRAINT fk_loyalty_memberships_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;
    END IF;
END $$;

-- Specifically reload postgrest schema cache
NOTIFY pgrst, 'reload schema';
