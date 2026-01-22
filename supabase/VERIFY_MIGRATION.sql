-- ==========================================
-- VERIFY MIGRATION SUCCESS
-- Run this to check that tenant_id was added correctly
-- ==========================================

-- 1. Check tenants table exists and has data
SELECT 'Tenants Table' as check_name, COUNT(*) as count, 
  string_agg(name, ', ') as tenant_names
FROM public.tenants;

-- 2. Check tenant_id column exists in all tables
SELECT 
  'tenant_id columns' as check_name,
  COUNT(*) as tables_with_tenant_id,
  string_agg(table_name, ', ') as table_names
FROM information_schema.columns
WHERE column_name = 'tenant_id' 
  AND table_schema = 'public';

-- 3. Check data has been backfilled
SELECT 
  'profiles' as table_name,
  COUNT(*) as total_rows,
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END) as rows_with_tenant,
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END) as rows_without_tenant
FROM public.profiles
UNION ALL
SELECT 
  'products',
  COUNT(*),
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END),
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END)
FROM public.products
UNION ALL
SELECT 
  'customers',
  COUNT(*),
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END),
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END)
FROM public.customers
UNION ALL
SELECT 
  'sales',
  COUNT(*),
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END),
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END)
FROM public.sales;

-- 4. Check which tenant your data is assigned to
SELECT 
  t.name as tenant_name,
  t.type as tenant_type,
  (SELECT COUNT(*) FROM profiles WHERE tenant_id = t.id) as profiles,
  (SELECT COUNT(*) FROM products WHERE tenant_id = t.id) as products,
  (SELECT COUNT(*) FROM customers WHERE tenant_id = t.id) as customers,
  (SELECT COUNT(*) FROM sales WHERE tenant_id = t.id) as sales
FROM public.tenants t
ORDER BY t.name;

-- If all looks good, you should see:
-- ✅ 2 tenants (Platform Admin & Default Store)
-- ✅ tenant_id in multiple tables
-- ✅ All your data assigned to "Default Store" tenant
-- ✅ No rows_without_tenant (all should have tenant_id)
