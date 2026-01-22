-- Add missing columns for stability and multi-tenancy
-- These should have been in Part 1 or 2, but we add them here to ensure they exist.

DO $$
BEGIN
    -- 1. Add idempotency_key to sales
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sales' AND column_name = 'idempotency_key') THEN
        ALTER TABLE public.sales ADD COLUMN idempotency_key TEXT;
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency ON public.sales(idempotency_key) WHERE idempotency_key IS NOT NULL;
    END IF;

    -- 2. Add tenant_id to sale_items (mandatory for strict isolation)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'sale_items' AND column_name = 'tenant_id') THEN
        ALTER TABLE public.sale_items ADD COLUMN tenant_id UUID REFERENCES public.tenants(id);
        CREATE INDEX IF NOT EXISTS idx_sale_items_tenant ON public.sale_items(tenant_id);
    END IF;

    -- 3. Add sequence if not exists
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'sales_invoice_seq') THEN
        CREATE SEQUENCE public.sales_invoice_seq START 1000;
    END IF;
END $$;
