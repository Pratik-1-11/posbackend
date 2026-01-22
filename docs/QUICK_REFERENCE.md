# Multi-Tenant POS System - Quick Reference

## 🎯 Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│                     PLATFORM LEVEL                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Super Tenant (Platform Owner)                            │  │
│  │  - Super Admin User                                       │  │
│  │  - Access to ALL tenant data                              │  │
│  │  - Tenant management                                      │  │
│  │  - Impersonation capability                               │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     VENDOR LEVEL                                 │
│                                                                   │
│  ┌──────────────────────┐  ┌──────────────────────┐             │
│  │ Vendor Tenant 1      │  │ Vendor Tenant 2      │             │
│  │ (Hamro Mart)         │  │ (My Mart)            │   ...       │
│  │                      │  │                      │             │
│  │ Users:               │  │ Users:               │             │
│  │ • Vendor Admin       │  │ • Vendor Admin       │             │
│  │ • Vendor Manager     │  │ • Cashier 1          │             │
│  │ • Cashier 1, 2       │  │ • Cashier 2          │             │
│  │                      │  │                      │             │
│  │ Data:                │  │ Data:                │             │
│  │ • Products           │  │ • Products           │             │
│  │ • Customers          │  │ • Customers          │             │
│  │ • Sales              │  │ • Sales              │             │
│  │ • Settings           │  │ • Settings           │             │
│  └──────────────────────┘  └──────────────────────┘             │
│           ▲                          ▲                           │
│           │                          │                           │
│           └──────────────────────────┘                           │
│              Complete Data Isolation                             │
│         (tenant_id + RLS policies)                               │
└─────────────────────────────────────────────────────────────────┘
```

## 📊 User Roles & Permissions Matrix

| Feature/Action | SUPER_ADMIN | VENDOR_ADMIN | VENDOR_MANAGER | CASHIER | INVENTORY_MANAGER |
|----------------|:----------:|:------------:|:--------------:|:-------:|:-----------------:|
| **Tenants** |
| Create Tenant | ✅ | ❌ | ❌ | ❌ | ❌ |
| Manage Own Tenant | ✅ | ✅ | ❌ | ❌ | ❌ |
| View All Tenants | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Users** |
| Create User | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |
| Edit User | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |
| Delete User | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |
| **Products** |
| View Products | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own) | ✅ (own) |
| Create Product | ✅ | ✅ | ✅ | ❌ | ✅ |
| Edit Product | ✅ | ✅ | ✅ | ❌ | ✅ |
| Delete Product | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Sales** |
| View Sales | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own) | ✅ (own) |
| Create Sale | ✅ | ✅ | ✅ | ✅ | ❌ |
| Refund Sale | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Reports** |
| Daily Reports | ✅ (all) | ✅ (own) | ✅ (own) | ❌ | ❌ |
| Analytics | ✅ (all) | ✅ (own) | ✅ (own) | ❌ | ❌ |
| Platform Analytics | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Customers** |
| View Customers | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own) | ❌ |
| Create Customer | ✅ | ✅ | ✅ | ✅ | ❌ |
| Edit Customer | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Settings** |
| Edit Settings | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |
| **Advanced** |
| Impersonate User | ✅ | ❌ | ❌ | ❌ | ❌ |
| View Audit Logs | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |

## 🔐 Data Flow: Request → Response

```
1. Client Request
   │
   ├─► JWT Token (contains user_id)
   │
   ▼
2. Authentication Middleware
   │
   ├─► Validates JWT
   ├─► Extracts user_id
   └─► Sets req.user = { id: user_id }
   │
   ▼
3. Tenant Resolver Middleware
   │
   ├─► Queries: SELECT tenant_id, role FROM profiles WHERE id = user_id
   ├─► Validates tenant is active
   ├─► Sets req.tenant = { id, name, type, isSuperAdmin }
   └─► Sets req.userRole = role
   │
   ▼
4. Authorization Middleware (if applied)
   │
   ├─► Checks req.userRole against allowed roles
   └─► Returns 403 if unauthorized
   │
   ▼
5. Controller Logic
   │
   ├─► Applies scopeToTenant() to queries
   │   │
   │   ├─► If SUPER_ADMIN: No filter (see all data)
   │   └─► If regular user: WHERE tenant_id = req.tenant.id
   │
   └─► Validates cross-references belong to same tenant
   │
   ▼
6. Database (RLS Enabled)
   │
   ├─► RLS policies enforce tenant isolation
   └─► auth.uid() and helper functions check permissions
   │
   ▼
7. Response to Client
   │
   └─► Only tenant-scoped data returned
```

## 🗄️ Key Database Tables

### Core Tenant Tables

```sql
tenants
├─ id (UUID, PK)
├─ name
├─ slug (unique)
├─ type (super | vendor)
├─ subscription_tier (basic | pro | enterprise)
└─ subscription_status (active | trial | suspended | cancelled)

profiles (users)
├─ id (UUID, PK, FK → auth.users)
├─ tenant_id (FK → tenants)
├─ role (SUPER_ADMIN | VENDOR_ADMIN | VENDOR_MANAGER | CASHIER | INVENTORY_MANAGER)
├─ full_name
└─ email

audit_logs
├─ id (UUID, PK)
├─ actor_id (FK → auth.users)
├─ tenant_id (FK → tenants)
├─ action (create | update | delete | impersonate)
├─ entity_type
├─ entity_id
└─ changes (JSONB)
```

### Business Tables (All have tenant_id)

```
products → tenant_id
customers → tenant_id
sales → tenant_id
categories → tenant_id
suppliers → tenant_id
expenses → tenant_id
purchases → tenant_id
settings → tenant_id
branches → tenant_id
```

## 🛠️ Code Patterns

### Pattern 1: Reading Data (GET)

```javascript
// ❌ WRONG - No tenant scoping
const { data } = await supabase.from('products').select('*');

// ✅ CORRECT - Always use scopeToTenant
const { scopeToTenant } = require('../utils/tenantQuery');

let query = supabase.from('products').select('*');
query = scopeToTenant(query, req, 'products');
const { data } = await query;
```

### Pattern 2: Creating Data (POST)

```javascript
// ❌ WRONG - Client could manipulate tenant_id
const { data } = await supabase
  .from('products')
  .insert([req.body]);

// ✅ CORRECT - Force tenant_id from context
const { addTenantToPayload } = require('../utils/tenantQuery');

const dataWithTenant = addTenantToPayload(req.body, req);
const { data } = await supabase
  .from('products')
  .insert([dataWithTenant]);
```

### Pattern 3: Updating Data (PUT)

```javascript
// ❌ WRONG - No ownership validation
const { data } = await supabase
  .from('products')
  .update(updates)
  .eq('id', productId);

// ✅ CORRECT - Validate ownership first
const { ensureTenantOwnership } = require('../utils/tenantQuery');

await ensureTenantOwnership(supabase, req, 'products', productId);

const { data } = await supabase
  .from('products')
  .update(updates)
  .eq('id', productId)
  .eq('tenant_id', req.tenant.id);  // Double-check
```

### Pattern 4: Route Protection

```javascript
const express = require('express');
const { authenticate } = require('../middleware/auth');
const { resolveTenant } = require('../middleware/tenantResolver');
const { canManageProducts } = require('../middleware/authorization');

const router = express.Router();

// Apply middleware in correct order
router.use(authenticate);      // 1. Authenticate user
router.use(resolveTenant);     // 2. Resolve tenant

// Public routes (within tenant)
router.get('/', productController.getAll);  // Scoped to tenant

// Protected routes
router.post('/', 
  canManageProducts,  // 3. Check permission
  productController.create
);
```

## 📋 Pre-Flight Checklist

Before deploying multi-tenant system:

### Database
- [ ] Backup created
- [ ] Migration script reviewed
- [ ] Migration executed successfully
- [ ] All tables have `tenant_id`
- [ ] RLS policies enabled
- [ ] Helper functions created
- [ ] Indexes on `tenant_id` created

### Backend
- [ ] Tenant resolver middleware added
- [ ] Authorization middleware added
- [ ] All controllers updated to use `scopeToTenant`
- [ ] All create operations use `addTenantToPayload`
- [ ] All update operations use `ensureTenantOwnership`
- [ ] Routes protected with role middleware
- [ ] Admin routes created
- [ ] Audit logging implemented

### Testing
- [ ] Data isolation verified (Vendor A cannot see Vendor B data)
- [ ] Super Admin can access all tenants
- [ ] Role permissions tested for each role
- [ ] Cross-tenant operations blocked
- [ ] Foreign key validation across tenants tested
- [ ] Load testing completed
- [ ] Security audit passed

### Deployment
- [ ] Staging tested
- [ ] Documentation updated
- [ ] Team trained
- [ ] Rollback plan ready
- [ ] Monitoring configured

## 🆘 Emergency Rollback

If migration fails:

```sql
-- 1. Disable RLS
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales DISABLE ROW LEVEL SECURITY;
-- ... for all tables

-- 2. Restore from backup
psql -h host -U user -d db < backup.sql

-- 3. Revert application to previous version

-- 4. Investigate and fix issues

-- 5. Re-attempt migration
```

## 📚 File Reference

| File | Purpose |
|------|---------|
| `MULTI_TENANT_ARCHITECTURE.md` | Complete architecture spec |
| `IMPLEMENTATION_GUIDE.md` | Step-by-step implementation |
| `011_multi_tenant_migration.sql` | Database migration script |
| `tenantResolver.js` | Tenant resolution middleware |
| `authorization.js` | RBAC middleware |
| `tenantQuery.js` | Query helper utilities |
| `product.controller.tenant-aware.js` | Example controller |

## 🔗 Key Concepts

1. **Single Database, Shared Schema**: All tenants share the same database and tables
2. **Tenant Isolation**: Enforced via `tenant_id` foreign key + RLS policies
3. **Super Admin Bypass**: `is_super_admin()` function allows platform owner to access all data
4. **Middleware Chain**: Auth → Tenant Resolution → Authorization → Controller
5. **Defense in Depth**: Tenant checks at middleware level AND database level (RLS)
6. **Audit Everything**: All admin actions logged to `audit_logs` table

## 🎓 Learning Resources

- Read: `MULTI_TENANT_ARCHITECTURE.md` for detailed explanations
- Study: `product.controller.tenant-aware.js` for implementation patterns
- Follow: `IMPLEMENTATION_GUIDE.md` for step-by-step instructions
- Test: Each phase thoroughly before moving to next

---

**Quick Start:** Follow `IMPLEMENTATION_GUIDE.md` checklist from Phase 1  
**Questions?** Review architecture document first, then check examples  
**Ready to Deploy?** Complete all checklist items and run verification commands
