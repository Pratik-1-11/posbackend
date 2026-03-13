
-- Migration: 102_bank_reconciliation_and_accounting_audit.sql
-- Purpose: Implement Bank Reconciliation and Accounting-specific Audit infrastructure.

-- 1. Enhance Journal Lines for Reconciliation
ALTER TABLE public.journal_entry_lines 
ADD COLUMN IF NOT EXISTS is_reconciled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS reconciliation_id UUID;

-- 2. Create Bank Reconciliations Table
CREATE TABLE IF NOT EXISTS public.bank_reconciliations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    account_id UUID REFERENCES public.accounts(id) ON DELETE RESTRICT,
    statement_date DATE NOT NULL,
    starting_balance NUMERIC(15, 2) DEFAULT 0,
    ending_balance NUMERIC(15, 2) DEFAULT 0,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'finalized')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    finalized_at TIMESTAMPTZ,
    finalized_by UUID REFERENCES auth.users(id),
    UNIQUE(tenant_id, account_id, statement_date)
);

-- Enable RLS
ALTER TABLE public.bank_reconciliations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "View bank_recs in own tenant" ON public.bank_reconciliations
FOR SELECT USING (tenant_id = public.get_user_tenant_id());

-- 3. Add foreign key link to journal_entry_lines
ALTER TABLE public.journal_entry_lines
ADD CONSTRAINT fk_reconciliation 
FOREIGN KEY (reconciliation_id) 
REFERENCES public.bank_reconciliations(id) ON DELETE SET NULL;

-- 4. Create Audit Trigger for Accounts and Journal Entries
-- This ensures that any manual changes to the ledger are tracked with high priority.

CREATE OR REPLACE FUNCTION public.log_accounting_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.audit_logs (
        actor_id,
        tenant_id,
        action,
        entity_type,
        entity_id,
        changes
    ) VALUES (
        public.get_user_id(),
        COALESCE(NEW.tenant_id, OLD.tenant_id),
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        jsonb_build_object(
            'old', to_jsonb(OLD),
            'new', to_jsonb(NEW)
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply to Accounts (preventing silent changes to system accounts)
DROP TRIGGER IF EXISTS trg_audit_accounts ON public.accounts;
CREATE TRIGGER trg_audit_accounts
AFTER UPDATE OR DELETE ON public.accounts
FOR EACH ROW EXECUTE FUNCTION public.log_accounting_changes();

-- Apply to Journal Entries (tracking manual edits)
DROP TRIGGER IF EXISTS trg_audit_journals ON public.journal_entries;
CREATE TRIGGER trg_audit_journals
AFTER INSERT OR UPDATE OR DELETE ON public.journal_entries
FOR EACH ROW EXECUTE FUNCTION public.log_accounting_changes();
