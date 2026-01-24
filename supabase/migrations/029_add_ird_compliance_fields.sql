-- Migration: 029_add_ird_compliance_fields.sql
-- Description: Add fields required for IRD Nepal compliance

-- 1. Add PAN Number to Customers
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS pan_number TEXT;

-- 2. Add PAN/VAT Number to Tenants (Store Info)
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS pan_number TEXT;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.tenants ADD COLUMN IF NOT EXISTS phone TEXT;

-- 3. Add Invoice Type to Sales
-- IRD requires distinguishing between Tax Invoice and Credit Note
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS invoice_type TEXT DEFAULT 'tax-invoice' CHECK (invoice_type IN ('tax-invoice', 'credit-note', 'abbreviated-tax-invoice'));

-- 4. Create a View for IRD Sales Book
CREATE OR REPLACE VIEW public.ird_sales_book AS
SELECT 
    s.created_at::DATE as date,
    s.invoice_number,
    'tax-invoice' as invoice_type, -- Default to tax-invoice for sales
    COALESCE(s.customer_name, 'Walk-in') as customer_name,
    c.pan_number as customer_pan,
    s.taxable_amount,
    s.vat_amount,
    (s.total_amount - s.taxable_amount - s.vat_amount) as non_taxable_amount,
    s.total_amount,
    COALESCE(s.payment_method, 'cash') as payment_method,
    COALESCE(p.full_name, 'System') as cashier_name,
    s.tenant_id,
    s.status
FROM public.sales s
LEFT JOIN public.customers c ON s.customer_id = c.id
LEFT JOIN public.profiles p ON s.cashier_id = p.id

UNION ALL

-- Include Returns as Credit Notes
SELECT 
    r.created_at::DATE as date,
    'CN-' || s.invoice_number as invoice_number,
    'credit-note' as invoice_type,
    COALESCE(s.customer_name, 'Walk-in') as customer_name,
    c.pan_number as customer_pan,
    -(r.total_refund_amount / 1.13) as taxable_amount, -- Backward calculate taxable if not stored
    -(r.total_refund_amount - (r.total_refund_amount / 1.13)) as vat_amount,
    0 as non_taxable_amount,
    -r.total_refund_amount as total_amount,
    'refund' as payment_method,
    COALESCE(p.full_name, 'System') as cashier_name,
    r.tenant_id,
    'completed' as status
FROM public.returns r
JOIN public.sales s ON r.sale_id = s.id
LEFT JOIN public.customers c ON s.customer_id = c.id
LEFT JOIN public.profiles p ON r.cashier_id = p.id;
