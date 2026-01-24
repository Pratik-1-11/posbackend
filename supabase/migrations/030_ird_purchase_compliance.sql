-- Migration: 030_ird_purchase_compliance.sql
-- Description: Add fields for IRD Nepal Purchase Book compliance

-- 1. Update Suppliers with PAN/VAT
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS pan_number TEXT;

-- 2. Update Purchases with IRD compliant fields
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS bill_number TEXT;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS taxable_amount NUMERIC(10, 2) DEFAULT 0;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS vat_amount NUMERIC(10, 2) DEFAULT 0;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS non_taxable_amount NUMERIC(10, 2) DEFAULT 0;

-- 3. Create IRD Purchase Book View
CREATE OR REPLACE VIEW public.ird_purchase_book AS
SELECT 
    p.purchase_date::DATE as date,
    COALESCE(p.bill_number, 'N/A') as bill_number,
    p.supplier_name,
    s.pan_number as supplier_pan,
    p.taxable_amount,
    p.vat_amount,
    p.non_taxable_amount,
    p.total_amount,
    p.status,
    p.tenant_id
FROM public.purchases p
LEFT JOIN public.suppliers s ON p.supplier_name = s.name AND p.tenant_id = s.tenant_id;
