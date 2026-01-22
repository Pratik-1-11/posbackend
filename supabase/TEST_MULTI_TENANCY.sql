-- ==========================================
-- TEST MULTI-TENANCY IS WORKING
-- Run these tests to verify tenant isolation
-- ==========================================

-- TEST 1: Check RLS is enabled on all tables
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('tenants', 'profiles', 'products', 'customers', 'sales')
ORDER BY tablename;
-- All should show TRUE for rls_enabled

-- TEST 2: Check all helper functions exist
SELECT 
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'get_user_tenant_id',
    'is_super_admin',
    'is_vendor_admin',
    'can_manage_products'
  )
ORDER BY routine_name;
-- Should return 4 functions

-- TEST 3: Verify all data is assigned to tenants
SELECT 
  'Profiles' as table_name,
  COUNT(*) as total_rows,
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END) as with_tenant,
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END) as without_tenant
FROM public.profiles
UNION ALL
SELECT 'Products', COUNT(*), 
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END),
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END)
FROM public.products
UNION ALL
SELECT 'Customers', COUNT(*), 
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END),
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END)
FROM public.customers
UNION ALL
SELECT 'Sales', COUNT(*), 
  COUNT(CASE WHEN tenant_id IS NOT NULL THEN 1 END),
  COUNT(CASE WHEN tenant_id IS NULL THEN 1 END)
FROM public.sales;
-- "without_tenant" should be 0 for all tables

-- TEST 4: Check tenant distribution
SELECT 
  t.name as tenant_name,
  t.type as tenant_type,
  (SELECT COUNT(*) FROM profiles WHERE tenant_id = t.id) as profiles_count,
  (SELECT COUNT(*) FROM products WHERE tenant_id = t.id) as products_count,
  (SELECT COUNT(*) FROM customers WHERE tenant_id = t.id) as customers_count,
  (SELECT COUNT(*) FROM sales WHERE tenant_id = t.id) as sales_count
FROM public.tenants t
ORDER BY t.created_at;

-- Expected result:
-- Platform Admin (super): Should have your Super Admin user only
-- Default Store (vendor): Should have all your existing data

-- TEST 5: Check indexes exist
SELECT 
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE '%tenant%'
ORDER BY tablename, indexname;
-- Should show multiple tenant-related indexes

-- TEST 6: Verify foreign key constraints
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND kcu.column_name = 'tenant_id'
ORDER BY tc.table_name;
-- Should show tenant_id foreign keys

-- ==========================================
-- SUMMARY
-- ==========================================
-- If all tests pass, your multi-tenant system is ready!
-- ✅ RLS enabled
-- ✅ Helper functions created
-- ✅ All data has tenant_id
-- ✅ Indexes for performance
-- ✅ Foreign key constraints for integrity
