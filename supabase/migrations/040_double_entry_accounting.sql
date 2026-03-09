-- Migration: 040_double_entry_accounting.sql
-- Purpose: Implement Double-Entry Accounting System core tables and auto-journal logic.

-- 1. Create Chart of Accounts (COA)
CREATE TABLE IF NOT EXISTS public.accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    is_system_account BOOLEAN DEFAULT false,
    system_code TEXT UNIQUE, -- e.g., 'CASH', 'SALES_REVENUE', 'VAT_PAYABLE', 'AR', 'COGS', 'INVENTORY', 'SALES_DISCOUNT'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(tenant_id, code)
);

-- Enable RLS for Accounts
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "View accounts in own tenant" ON public.accounts;
CREATE POLICY "View accounts in own tenant" ON public.accounts
FOR SELECT USING (tenant_id = public.get_user_tenant_id());

-- 2. Create Journal Entries
CREATE TABLE IF NOT EXISTS public.journal_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE,
    reference_id UUID, -- Link to sales.id, purchases.id, etc.
    reference_type TEXT NOT NULL CHECK (reference_type IN ('SALE', 'PURCHASE', 'EXPENSE', 'PAYMENT', 'MANUAL')),
    description TEXT,
    entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

-- Enable RLS for Journal Entries
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "View journals in own tenant" ON public.journal_entries;
CREATE POLICY "View journals in own tenant" ON public.journal_entries
FOR SELECT USING (tenant_id = public.get_user_tenant_id());

-- 3. Create Journal Entry Lines
CREATE TABLE IF NOT EXISTS public.journal_entry_lines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entry_id UUID REFERENCES public.journal_entries(id) ON DELETE CASCADE,
    account_id UUID REFERENCES public.accounts(id) ON DELETE RESTRICT,
    debit NUMERIC(15, 2) NOT NULL DEFAULT 0,
    credit NUMERIC(15, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (debit >= 0 AND credit >= 0),
    CHECK ((debit > 0 AND credit = 0) OR (debit = 0 AND credit > 0) OR (debit = 0 AND credit = 0))
);

-- Note: We do not enforce the sum(debit)=sum(credit) check at the DB schema level due to cross-row complexity,
-- but our functions MUST ensure it.

-- Enable RLS for Journal Entry Lines
ALTER TABLE public.journal_entry_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "View journal lines in own tenant" ON public.journal_entry_lines;
CREATE POLICY "View journal lines in own tenant" ON public.journal_entry_lines
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.journal_entries 
        WHERE id = public.journal_entry_lines.entry_id AND tenant_id = public.get_user_tenant_id()
    )
);

-- 4. Function to Seed Default Accounts for a new Tenant
CREATE OR REPLACE FUNCTION public.seed_default_accounts(p_tenant_id UUID)
RETURNS void AS $$
BEGIN
    INSERT INTO public.accounts (tenant_id, code, name, type, is_system_account, system_code)
    VALUES
        (p_tenant_id, '1000', 'Cash & Bank', 'asset', true, 'CASH'),
        (p_tenant_id, '1100', 'Accounts Receivable', 'asset', true, 'AR'),
        (p_tenant_id, '1200', 'Inventory Asset', 'asset', true, 'INVENTORY'),
        (p_tenant_id, '2000', 'Accounts Payable', 'liability', true, 'AP'),
        (p_tenant_id, '2100', 'VAT Payable', 'liability', true, 'VAT_PAYABLE'),
        (p_tenant_id, '3000', 'Owner''s Equity', 'equity', true, 'EQUITY'),
        (p_tenant_id, '4000', 'Sales Revenue', 'revenue', true, 'SALES_REVENUE'),
        (p_tenant_id, '4100', 'Sales Discounts', 'revenue', true, 'SALES_DISCOUNT'),
        (p_tenant_id, '5000', 'Cost of Goods Sold (COGS)', 'expense', true, 'COGS'),
        (p_tenant_id, '5100', 'General Expenses', 'expense', true, 'GENERAL_EXPENSE')
    ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Auto-Seed for existing tenants
DO $$
DECLARE
    v_tenant RECORD;
BEGIN
    FOR v_tenant IN SELECT id FROM public.tenants LOOP
        PERFORM public.seed_default_accounts(v_tenant.id);
    END LOOP;
END;
$$;
