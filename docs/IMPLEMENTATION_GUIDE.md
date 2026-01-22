# Multi-Tenant POS System - Implementation Guide

## 📋 Overview

This guide provides step-by-step instructions to migrate your existing single-tenant POS system to a multi-tenant SaaS architecture.

## 📚 Documentation Structure

```
backend/
├── docs/
│   ├── MULTI_TENANT_ARCHITECTURE.md    # Complete architecture specification
│   ├── IMPLEMENTATION_GUIDE.md         # This file
│   └── examples/
│       └── product.controller.tenant-aware.js  # Example controller
├── supabase/
│   └── migrations/
│       └── 011_multi_tenant_migration.sql      # Database migration
└── src/
    ├── middleware/
    │   ├── tenantResolver.js           # Tenant resolution middleware
    │   └── authorization.js            # RBAC middleware
    └── utils/
        └── tenantQuery.js              # Tenant query helpers
```

## 🚀 Implementation Checklist

### Phase 1: Database Migration

- [ ] **1.1 Backup Existing Database**
  ```bash
  # Create backup before migration
  pg_dump your_database > backup_$(date +%Y%m%d_%H%M%S).sql
  ```

- [ ] **1.2 Review Migration Script**
  - Read `backend/supabase/migrations/011_multi_tenant_migration.sql`
  - Understand all changes being made
  - Verify tenant IDs in the script

- [ ] **1.3 Execute Migration**
  ```bash
  # Option 1: Using Supabase CLI (recommended)
  supabase db push

  # Option 2: Direct SQL execution
  psql -h your-host -U your-user -d your-db -f backend/supabase/migrations/011_multi_tenant_migration.sql
  ```

- [ ] **1.4 Verify Migration**
  ```sql
  -- Check tenants created
  SELECT * FROM public.tenants;

  -- Check tenant_id populated
  SELECT COUNT(*) FROM public.products WHERE tenant_id IS NOT NULL;
  SELECT COUNT(*) FROM public.customers WHERE tenant_id IS NOT NULL;
  SELECT COUNT(*) FROM public.sales WHERE tenant_id IS NOT NULL;

  -- Verify RLS policies
  SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public';
  ```

### Phase 2: Backend Code Updates

- [ ] **2.1 Install Dependencies**
  ```bash
  cd backend
  npm install express-rate-limit bull redis
  ```

- [ ] **2.2 Update Environment Variables**
  ```bash
  # Add to backend/.env
  SUPABASE_URL=your_supabase_url
  SUPABASE_SERVICE_KEY=your_service_key
  JWT_SECRET=your_jwt_secret
  REDIS_URL=redis://localhost:6379  # Optional: for caching
  ```

- [ ] **2.3 Update Authentication Middleware**
  - Ensure `req.user` is populated with authenticated user
  - User must have `id` field from Supabase Auth

- [ ] **2.4 Add Tenant Resolution Middleware**
  ```javascript
  // In your app.js or server.js
  const { resolveTenant } = require('./src/middleware/tenantResolver');
  const { authenticate } = require('./src/middleware/auth'); // Your existing auth

  // Apply to all API routes
  app.use('/api', authenticate);      // First authenticate
  app.use('/api', resolveTenant);     // Then resolve tenant
  ```

- [ ] **2.5 Update All Controllers**
  For each controller, update to use tenant-scoped queries:

  **Before:**
  ```javascript
  const { data } = await supabase
    .from('products')
    .select('*');
  ```

  **After:**
  ```javascript
  const { scopeToTenant } = require('../utils/tenantQuery');

  let query = supabase.from('products').select('*');
  query = scopeToTenant(query, req, 'products');
  const { data } = await query;
  ```

  **Controllers to update:**
  - [ ] `product.controller.js`
  - [ ] `customer.controller.js`
  - [ ] `sale.controller.js`
  - [ ] `user.controller.js`
  - [ ] `expense.controller.js`
  - [ ] `purchase.controller.js`
  - [ ] `report.controller.js`

- [ ] **2.6 Add Tenant Validation to Create Operations**
  ```javascript
  const { addTenantToPayload } = require('../utils/tenantQuery');

  // In create function
  const dataWithTenant = addTenantToPayload(req.body, req);
  const { data } = await supabase.from('products').insert([dataWithTenant]);
  ```

- [ ] **2.7 Add Cross-Tenant Validation**
  ```javascript
  const { ensureTenantOwnership } = require('../utils/tenantQuery');

  // In update/delete functions
  await ensureTenantOwnership(supabase, req, 'products', productId);
  ```

### Phase 3: Create Admin Controllers

- [ ] **3.1 Create Tenant Management Controller**
  ```javascript
  // backend/src/controllers/admin.controller.js
  exports.createTenant = async (req, res) => {
    // Only SUPER_ADMIN can access this
    // Create new tenant
  };

  exports.getAllTenants = async (req, res) => {
    // List all tenants (SUPER_ADMIN only)
  };
  ```

- [ ] **3.2 Create Admin Routes**
  ```javascript
  // backend/src/routes/admin.routes.js
  const { requireSuperAdmin } = require('../middleware/authorization');

  router.use(authenticate);
  router.use(resolveTenant);
  router.use(requireSuperAdmin);

  router.post('/tenants', adminController.createTenant);
  router.get('/tenants', adminController.getAllTenants);
  ```

- [ ] **3.3 Implement Impersonation (Optional)**
  - Create `impersonateUser` endpoint
  - Create `stopImpersonation` endpoint
  - Add audit logging for all impersonation actions

### Phase 4: Update Routes with Authorization

- [ ] **4.1 Add Role-Based Middleware to Routes**
  ```javascript
  const { 
    canManageProducts,
    canCreateSales,
    requireManager 
  } = require('../middleware/authorization');

  // Product routes
  router.post('/products', canManageProducts, productController.create);
  router.put('/products/:id', canManageProducts, productController.update);

  // Sales routes
  router.post('/sales', canCreateSales, saleController.create);

  // Reports
  router.get('/reports/daily', requireManager, reportController.daily);
  ```

- [ ] **4.2 Update All Route Files**
  - [ ] `product.routes.js`
  - [ ] `customer.routes.js`
  - [ ] `sale.routes.js`
  - [ ] `user.routes.js`
  - [ ] `report.routes.js`

### Phase 5: Frontend Updates

- [ ] **5.1 Store Tenant Context**
  ```typescript
  // After login, store tenant info
  interface TenantContext {
    id: string;
    name: string;
    slug: string;
    role: string;
  }

  // Save to localStorage or Context API
  ```

- [ ] **5.2 Update API Calls**
  - API calls already include JWT token
  - Backend middleware handles tenant resolution
  - No frontend changes needed for basic tenant scoping

- [ ] **5.3 Add Tenant Selector (Super Admin Only)**
  ```typescript
  // For Super Admin dashboard
  if (userRole === 'SUPER_ADMIN') {
    // Show tenant selector dropdown
    // Allow switching between tenants for support
  }
  ```

- [ ] **5.4 Update UI Based on Role**
  ```typescript
  // Hide/show features based on role
  {userRole === 'VENDOR_ADMIN' && (
    <Button onClick={manageUsers}>Manage Users</Button>
  )}

  {['VENDOR_ADMIN', 'VENDOR_MANAGER'].includes(userRole) && (
    <Link to="/reports">Reports</Link>
  )}
  ```

### Phase 6: User Migration

- [ ] **6.1 Create Super Admin User**
  ```sql
  -- Manually create super admin in Supabase Auth dashboard
  -- Then update profile
  UPDATE public.profiles
  SET 
    tenant_id = '00000000-0000-0000-0000-000000000001',  -- Super tenant
    role = 'SUPER_ADMIN'
  WHERE email = 'your-admin@email.com';
  ```

- [ ] **6.2 Update Existing Users**
  ```sql
  -- Assign all existing users to default vendor tenant
  UPDATE public.profiles
  SET 
    tenant_id = '00000000-0000-0000-0000-000000000002',  -- Default vendor
    role = CASE
      WHEN role IN ('admin', 'super_admin') THEN 'VENDOR_ADMIN'
      WHEN role IN ('manager', 'branch_admin') THEN 'VENDOR_MANAGER'
      WHEN role = 'inventory_manager' THEN 'INVENTORY_MANAGER'
      ELSE 'CASHIER'
    END
  WHERE tenant_id IS NULL;
  ```

- [ ] **6.3 Verify User Roles**
  ```sql
  SELECT 
    p.email,
    p.role,
    t.name as tenant_name,
    t.type as tenant_type
  FROM public.profiles p
  JOIN public.tenants t ON p.tenant_id = t.id;
  ```

### Phase 7: Testing

- [ ] **7.1 Create Test Tenants**
  ```sql
  INSERT INTO public.tenants (name, slug, type, contact_email, subscription_status)
  VALUES 
    ('Hamro Mart', 'hamro-mart', 'vendor', 'hamromartadmin@gmail.com', 'active'),
    ('My Mart', 'my-mart', 'vendor', 'mymartadmin@gmail.com', 'active');
  ```

- [ ] **7.2 Create Test Users**
  - Create user in Supabase Auth
  - Create corresponding profile with correct tenant_id and role

- [ ] **7.3 Test Data Isolation**
  Test Scenario 1: Cross-tenant product access
  ```
  1. Login as Hamro Mart admin
  2. Create product "Product A"
  3. Logout
  4. Login as My Mart admin
  5. Try to fetch all products
  6. Verify "Product A" is NOT in the list ✅
  ```

  Test Scenario 2: Cross-tenant sale creation
  ```
  1. Login as Hamro Mart cashier
  2. Get Hamro Mart products
  3. Try to create sale with My Mart product ID
  4. Verify error: "Product not found" ✅
  ```

  Test Scenario 3: Super Admin access
  ```
  1. Login as Super Admin
  2. Fetch all products
  3. Verify products from ALL tenants are returned ✅
  ```

- [ ] **7.4 Test Authorization**
  ```
  Test: Cashier cannot manage products
  1. Login as Cashier
  2. Try to POST /api/products
  3. Verify error: "Insufficient permissions" ✅

  Test: Vendor Admin can manage users
  1. Login as Vendor Admin
  2. POST /api/users (create new cashier)
  3. Verify success ✅

  Test: Vendor Admin cannot create users for other tenants
  1. Login as Vendor Admin (Hamro Mart)
  2. Try to create user with tenant_id of My Mart
  3. Verify error or user created for Hamro Mart (force tenant) ✅
  ```

- [ ] **7.5 Load Testing**
  ```bash
  # Use tools like Apache Bench or Artillery
  artillery quick --count 10 --num 50 http://localhost:5000/api/products
  ```

### Phase 8: Security Audit

- [ ] **8.1 Review RLS Policies**
  - Test each policy with different roles
  - Ensure Super Admin bypass works
  - Verify no policy allows cross-tenant access

- [ ] **8.2 Test Edge Cases**
  - User with no tenant_id
  - Tenant with is_active = false
  - Expired subscription
  - Invalid JWT token
  - Manipulated tenant_id in request body

- [ ] **8.3 Audit Logging Verification**
  ```sql
  SELECT * FROM public.audit_logs ORDER BY created_at DESC LIMIT 10;
  ```

### Phase 9: Deployment

- [ ] **9.1 Deploy to Staging**
  - Run migration on staging database
  - Deploy backend code
  - Run smoke tests

- [ ] **9.2 Monitor Logs**
  - Check application logs for errors
  - Monitor database performance
  - Check audit logs for anomalies

- [ ] **9.3 Deploy to Production**
  - Schedule maintenance window
  - Backup production database
  - Run migration
  - Deploy application
  - Monitor closely for 24 hours

- [ ] **9.4 Post-Deployment Verification**
  - Test login for existing users
  - Test POS sales flow
  - Test product management
  - Test reports
  - Verify tenant isolation

### Phase 10: Documentation & Training

- [ ] **10.1 Document New Features**
  - User role definitions
  - Tenant management process
  - Super Admin capabilities

- [ ] **10.2 Train Support Team**
  - How to create new tenants
  - How to manage users
  - Troubleshooting common issues

- [ ] **10.3 Create Runbooks**
  - Tenant onboarding procedure
  - User management procedures
  - Emergency rollback procedure

## 🔍 Verification Commands

### Database Verification

```sql
-- Check all tables have tenant_id
SELECT 
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE column_name = 'tenant_id'
  AND table_schema = 'public';

-- Verify RLS is enabled
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = true;

-- Check helper functions exist
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%tenant%';
```

### Application Verification

```bash
# Test authenticated endpoints
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://localhost:5000/api/products

# Test role-based access
curl -X POST \
  -H "Authorization: Bearer CASHIER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Product"}' \
  http://localhost:5000/api/products
# Expected: 403 Forbidden
```

## ⚠️ Common Issues & Solutions

### Issue 1: "Tenant context missing"
**Cause:** Tenant resolver middleware not applied or auth middleware failed  
**Solution:** Ensure middleware order is correct: authenticate → resolveTenant

### Issue 2: "User profile not found"
**Cause:** User exists in auth.users but not in public.profiles  
**Solution:** Create profile entry for user with tenant_id

### Issue 3: RLS policy denies operation
**Cause:** RLS policy too restrictive or function not working  
**Solution:** Check helper functions (is_super_admin, get_user_tenant_id)

### Issue 4: Cross-tenant data visible
**Cause:** scopeToTenant not applied to query  
**Solution:** Always use scopeToTenant helper on queries

### Issue 5: Super Admin cannot see all data
**Cause:** is_super_admin() function returning false  
**Solution:** Verify user role is exactly 'SUPER_ADMIN' in profiles table

## 📈 Performance Optimization

- [ ] Add database indexes on tenant_id columns (already in migration)
- [ ] Implement Redis caching for tenant metadata
- [ ] Use connection pooling (Supabase handles this)
- [ ] Monitor slow queries with pg_stat_statements
- [ ] Consider table partitioning for very large tenants (future)

## 🔐 Security Best Practices

1. **Never trust client-provided tenant_id** - Always use `req.tenant.id`
2. **Always use scopeToTenant** for queries
3. **Validate foreign keys** belong to same tenant
4. **Log all admin actions** (impersonation, tenant management)
5. **Regularly audit** RLS policies and permissions
6. **Rate limit** API endpoints per tenant
7. **Monitor** for suspicious cross-tenant access attempts

## 📞 Support

For questions or issues during implementation:
- Review: `MULTI_TENANT_ARCHITECTURE.md`
- Check: Example controllers in `docs/examples/`
- Test: SQL migration in staging first

## 🎯 Success Criteria

Migration is successful when:
- ✅ All existing data has tenant_id
- ✅ RLS policies enforce tenant isolation
- ✅ Super Admin can access all tenants
- ✅ Regular users cannot access other tenants
- ✅ New entities automatically get tenant_id
- ✅ All tests pass
- ✅ No performance degradation
- ✅ Audit logs capture admin actions

## 🚦 Next Steps After Migration

1. **Implement tenant onboarding flow**
   - Registration page for new vendors
   - Email verification
   - Initial setup wizard

2. **Add subscription management**
   - Stripe/Razorpay integration
   - Billing dashboard
   - Usage tracking

3. **Build Super Admin dashboard**
   - Tenant overview
   - Platform analytics
   - Health monitoring

4. **Implement advanced features**
   - Multi-branch support per tenant
   - Custom branding per tenant
   - Tenant-specific settings
   - API rate limits by tier

---

**Last Updated:** 2026-01-01  
**Version:** 1.0  
**Status:** Ready for Implementation
