-- ============================================================================
-- CRITICAL HARDENING: Database Constraints, Indexes & Optimistic Locking
-- ============================================================================

-- 1. DATA INTEGRITY CONSTRAINTS (Prevent invalid non-negative values)
-- ============================================================================

-- 1.1 Products
ALTER TABLE IF EXISTS public.products 
  ADD CONSTRAINT products_stock_quantity_check CHECK (stock_quantity >= 0),
  ADD CONSTRAINT products_selling_price_check CHECK (selling_price >= 0),
  ADD CONSTRAINT products_cost_price_check CHECK (cost_price >= 0);

-- 1.2 Sales
ALTER TABLE IF EXISTS public.sales
  ADD CONSTRAINT sales_total_amount_check CHECK (total_amount >= 0),
  ADD CONSTRAINT sales_discount_amount_check CHECK (discount_amount >= 0),
  ADD CONSTRAINT sales_taxable_amount_check CHECK (taxable_amount >= 0),
  ADD CONSTRAINT sales_vat_amount_check CHECK (vat_amount >= 0);

-- 1.3 Sale Items
ALTER TABLE IF EXISTS public.sale_items
  ADD CONSTRAINT sale_items_quantity_check CHECK (quantity > 0),
  ADD CONSTRAINT sale_items_unit_price_check CHECK (unit_price >= 0),
  ADD CONSTRAINT sale_items_total_price_check CHECK (total_price >= 0);

-- 1.4 Customers
ALTER TABLE IF EXISTS public.customers
  ADD CONSTRAINT customers_total_credit_check CHECK (total_credit >= 0);

-- 1.5 Purchases
ALTER TABLE IF EXISTS public.purchases
  ADD CONSTRAINT purchases_quantity_check CHECK (quantity > 0),
  ADD CONSTRAINT purchases_unit_price_check CHECK (unit_price >= 0);

-- 1.6 Expenses
ALTER TABLE IF EXISTS public.expenses
  ADD CONSTRAINT expenses_amount_check CHECK (amount >= 0);


-- 2. PERFORMANCE INDEXES (Optimized for Multi-Tenant Lookups)
-- ============================================================================

-- 2.1 Inventory
CREATE INDEX IF NOT EXISTS idx_products_tenant_active ON public.products (tenant_id, is_active);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products (barcode);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products (category_id);

-- 2.2 Sales
CREATE INDEX IF NOT EXISTS idx_sales_tenant_created ON public.sales (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_status ON public.sales (status);
CREATE INDEX IF NOT EXISTS idx_sales_invoice ON public.sales (invoice_number);
CREATE INDEX IF NOT EXISTS idx_sales_cashier ON public.sales (cashier_id);

-- 2.3 Customers
CREATE INDEX IF NOT EXISTS idx_customers_tenant_phone ON public.customers (tenant_id, phone);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers (email);

-- 2.4 Audit & Logs
CREATE INDEX IF NOT EXISTS idx_audit_tenant_created ON public.audit_logs (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON public.audit_logs (entity_type, entity_id);

-- 2.5 Profiles
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles (email);

-- 2.6 Related Items
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items (sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON public.sale_items (product_id);


-- 3. OPTIMISTIC LOCKING (Prevent Race Conditions)
-- ============================================================================
ALTER TABLE IF EXISTS public.products ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;
ALTER TABLE IF EXISTS public.customers ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;
ALTER TABLE IF EXISTS public.sales ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;

-- 4. UTILITY INDEXES
CREATE INDEX IF NOT EXISTS idx_tenants_slug ON public.tenants (slug);
CREATE INDEX IF NOT EXISTS idx_branches_tenant ON public.branches (tenant_id);
