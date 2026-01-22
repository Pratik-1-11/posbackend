# Multi-Tenant SaaS Architecture for POS System

**Version:** 1.0  
**Date:** 2026-01-01  
**Status:** Design Specification

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Multi-Tenant Architecture Overview](#multi-tenant-architecture-overview)
3. [Database Schema Design](#database-schema-design)
4. [Authentication & Authorization Model](#authentication--authorization-model)
5. [Tenant Isolation Strategy](#tenant-isolation-strategy)
6. [API Design & Access Rules](#api-design--access-rules)
7. [User Flows & Examples](#user-flows--examples)
8. [Security Considerations](#security-considerations)
9. [Scalability & Best Practices](#scalability--best-practices)
10. [Migration Strategy](#migration-strategy)

---

## 1. Executive Summary

This document outlines the transformation of the existing single-tenant POS system into a **multi-tenant SaaS platform** that supports:

- **Super Tenant (Platform Owner):** Manages all vendors, provides support, and has global visibility
- **Vendor Tenants (Mart Owners):** Independent businesses operating their own POS systems
- **Users per Vendor:** Multiple staff members with role-based access control (RBAC)

**Key Design Principles:**
- Single database, shared schema with tenant isolation via `tenant_id`
- Centralized authentication using Supabase Auth
- Row-level security (RLS) enforced at database layer
- Middleware-based tenant resolution at API layer
- Extensible architecture for future features (subscriptions, analytics, multi-region)

---

## 2. Multi-Tenant Architecture Overview

### 2.1 Tenancy Model: Single Database, Shared Schema

We use the **shared database, shared schema** approach with tenant isolation via `tenant_id` foreign keys.

**Benefits:**
- ✅ Cost-effective (single database to maintain)
- ✅ Easy to deploy updates and patches
- ✅ Simplified backup and disaster recovery
- ✅ Cross-tenant analytics for platform owner
- ✅ Resource sharing and optimization

**Trade-offs:**
- ⚠️ Requires careful RLS policy design
- ⚠️ Potential noisy neighbor issues (mitigated with connection pooling and query optimization)
- ⚠️ Data isolation depends on application logic

### 2.2 Tenant Hierarchy

```
Platform (Super Tenant)
│
├── Vendor Tenant 1 (e.g., "Hamro Mart")
│   ├── User: Admin (hamromartadmin@gmail.com)
│   ├── User: Cashier 1 (hamromartcashier@gmail.com)
│   └── User: Cashier 2
│
├── Vendor Tenant 2 (e.g., "My Mart")
│   ├── User: Admin (mymartadmin@gmail.com)
│   └── User: Cashier(mymartcashier@gmail.com)
│
└── Vendor Tenant N...
```

### 2.3 Tenant Types

| Tenant Type | Description | Capabilities |
|-------------|-------------|--------------|
| **Super Tenant** | Platform owner/administrator | - Create/manage vendors<br>- Impersonate vendor users<br>- View all data across tenants<br>- Configure platform settings<br>- Access audit logs |
| **Vendor Tenant** | Individual mart/store | - Own products, sales, customers<br>- Manage staff users<br>- Configure business settings<br>- View own data only |

---

## 3. Database Schema Design

### 3.1 Core Multi-Tenant Tables

#### 3.1.1 Tenants Table

```sql
CREATE TABLE public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Tenant Identity
  name TEXT NOT NULL,                          -- e.g., "Hamro Mart"
  slug TEXT UNIQUE NOT NULL,                    -- e.g., "hamro-mart" (for subdomain/routing)
  type TEXT NOT NULL DEFAULT 'vendor'           -- 'super', 'vendor'
    CHECK (type IN ('super', 'vendor')),
  
  -- Business Information
  business_name TEXT,                           -- Official registered name
  business_registration_number TEXT,            -- PAN/VAT number
  contact_email TEXT NOT NULL,                  -- Primary contact
  contact_phone TEXT,
  address TEXT,
  
  -- Subscription & Status
  subscription_tier TEXT DEFAULT 'basic'        -- 'basic', 'pro', 'enterprise'
    CHECK (subscription_tier IN ('basic', 'pro', 'enterprise')),
  subscription_status TEXT DEFAULT 'active'     -- 'active', 'suspended', 'cancelled'
    CHECK (subscription_status IN ('active', 'trial', 'suspended', 'cancelled')),
  subscription_started_at TIMESTAMPTZ,
  subscription_expires_at TIMESTAMPTZ,
  
  -- Settings & Configuration
  settings JSONB DEFAULT '{}'::jsonb,           -- Tenant-specific settings
  
  -- Status & Metadata
  is_active BOOLEAN DEFAULT TRUE,
  onboarded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Super Admin Reference
  created_by UUID REFERENCES auth.users(id)
);

-- Indexes
CREATE INDEX idx_tenants_slug ON public.tenants(slug);
CREATE INDEX idx_tenants_type ON public.tenants(type);
CREATE INDEX idx_tenants_status ON public.tenants(subscription_status);
```

#### 3.1.2 Updated Profiles Table (Users)

```sql
-- Drop existing profiles table constraints
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;

-- Recreate profiles with tenant support
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Tenant Association
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  
  -- User Identity
  username TEXT,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  
  -- Role-Based Access Control
  role TEXT NOT NULL DEFAULT 'cashier'
    CHECK (role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER')),
  
  -- Branch Association (optional, for multi-branch vendors)
  branch_id UUID REFERENCES public.branches(id),
  
  -- User Settings
  settings JSONB DEFAULT '{}'::jsonb,
  
  -- Status & Metadata
  is_active BOOLEAN DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure unique email per tenant
  UNIQUE(tenant_id, email)
);

-- Indexes
CREATE INDEX idx_profiles_tenant ON public.profiles(tenant_id);
CREATE INDEX idx_profiles_role ON public.profiles(role);
CREATE INDEX idx_profiles_email ON public.profiles(email);
```

#### 3.1.3 Updated Branches Table

```sql
ALTER TABLE public.branches ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_branches_tenant ON public.branches(tenant_id);
```

### 3.2 Tenant-Scoped Business Tables

All existing business tables need `tenant_id` added:

```sql
-- Products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_products_tenant ON public.products(tenant_id);

-- Customers
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_customers_tenant ON public.customers(tenant_id);

-- Categories
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_categories_tenant ON public.categories(tenant_id);

-- Suppliers
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_suppliers_tenant ON public.suppliers(tenant_id);

-- Sales
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_sales_tenant ON public.sales(tenant_id);

-- Expenses
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_expenses_tenant ON public.expenses(tenant_id);

-- Purchases
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_purchases_tenant ON public.purchases(tenant_id);

-- Settings (now tenant-specific)
ALTER TABLE public.settings ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_settings_tenant ON public.settings(tenant_id);
```

### 3.3 Audit & Logging Tables

```sql
-- Audit Log for Super Admin actions
CREATE TABLE public.audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Who & Where
  actor_id UUID REFERENCES auth.users(id),      -- Who performed the action
  actor_role TEXT,                              -- Role at time of action
  tenant_id UUID REFERENCES public.tenants(id),  -- Which tenant was affected
  
  -- What & When
  action TEXT NOT NULL,                         -- 'create', 'update', 'delete', 'impersonate'
  entity_type TEXT NOT NULL,                    -- 'product', 'user', 'tenant', etc.
  entity_id UUID,                               -- ID of affected entity
  changes JSONB,                                -- Before/after values
  
  -- Context
  ip_address INET,
  user_agent TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_tenant ON public.audit_logs(tenant_id);
CREATE INDEX idx_audit_logs_actor ON public.audit_logs(actor_id);
CREATE INDEX idx_audit_logs_created ON public.audit_logs(created_at DESC);
```

### 3.4 Complete ERD

```
┌─────────────────┐
│   auth.users    │ (Supabase Auth)
└────────┬────────┘
         │
         │ 1:1
         ▼
┌─────────────────┐         ┌──────────────┐
│   profiles      │────────▶│   tenants    │
│  - tenant_id    │   N:1   │   - id       │
│  - role         │         │   - type     │
└─────────────────┘         └──────┬───────┘
                                   │
                                   │ 1:N
                    ┌──────────────┼────────────────┬──────────────┐
                    ▼              ▼                ▼              ▼
              ┌──────────┐   ┌──────────┐    ┌──────────┐  ┌──────────┐
              │ products │   │customers │    │  sales   │  │ branches │
              │tenant_id │   │tenant_id │    │tenant_id │  │tenant_id │
              └──────────┘   └──────────┘    └──────────┘  └──────────┘
```

---

## 4. Authentication & Authorization Model

### 4.1 Authentication Flow

```
1. User Login
   ↓
2. Supabase Auth validates credentials
   ↓
3. JWT Token issued with user ID
   ↓
4. Backend resolves tenant_id from profiles table
   ↓
5. Attach tenant_id to request context
   ↓
6. All queries scoped to tenant_id
```

### 4.2 Role Hierarchy & Permissions

```sql
-- Role Definitions
CREATE TYPE user_role AS ENUM (
  'SUPER_ADMIN',        -- Platform owner (super tenant)
  'VENDOR_ADMIN',       -- Vendor owner (full control within tenant)
  'VENDOR_MANAGER',     -- Store manager (limited admin rights)
  'CASHIER',            -- POS operator (sales only)
  'INVENTORY_MANAGER'   -- Stock management only
);
```

#### 4.2.1 Permission Matrix

| Resource | SUPER_ADMIN | VENDOR_ADMIN | VENDOR_MANAGER | CASHIER | INVENTORY_MANAGER |
|----------|-------------|--------------|----------------|---------|-------------------|
| **Tenants** |
| Create Tenant | ✅ | ❌ | ❌ | ❌ | ❌ |
| Update Tenant | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |
| Delete Tenant | ✅ | ❌ | ❌ | ❌ | ❌ |
| View Tenants | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own) | ✅ (own) |
| **Users** |
| Create User | ✅ (all tenants) | ✅ (own tenant) | ❌ | ❌ | ❌ |
| Update User | ✅ (all) | ✅ (own tenant) | ❌ | ❌ | ❌ |
| Delete User | ✅ (all) | ✅ (own tenant) | ❌ | ❌ | ❌ |
| **Products** |
| Create | ✅ | ✅ | ✅ | ❌ | ✅ |
| Read | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own) | ✅ (own) |
| Update | ✅ | ✅ | ✅ | ❌ | ✅ |
| Delete | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Sales** |
| Create Sale | ✅ | ✅ | ✅ | ✅ | ❌ |
| View Sales | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own sales) | ✅ (own) |
| Refund | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Customers** |
| Create | ✅ | ✅ | ✅ | ✅ | ❌ |
| Read | ✅ (all) | ✅ (own) | ✅ (own) | ✅ (own) | ❌ |
| Update | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Reports** |
| View Reports | ✅ (all) | ✅ (own) | ✅ (own) | ❌ | ✅ (own) |
| Export Data | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Settings** |
| Update Settings | ✅ | ✅ (own) | ❌ | ❌ | ❌ |
| **Audit Logs** |
| View Logs | ✅ (all) | ✅ (own) | ❌ | ❌ | ❌ |

### 4.3 Helper Functions for RBAC

```sql
-- Get current user's tenant_id
CREATE OR REPLACE FUNCTION public.get_user_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user is Super Admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'SUPER_ADMIN'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user is Vendor Admin (for their tenant)
CREATE OR REPLACE FUNCTION public.is_vendor_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'VENDOR_ADMIN'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user can manage users (Super Admin or Vendor Admin)
CREATE OR REPLACE FUNCTION public.can_manage_users()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if user can manage products
CREATE OR REPLACE FUNCTION public.can_manage_products()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() 
    AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER')
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;
```

---

## 5. Tenant Isolation Strategy

### 5.1 Database-Level Isolation (RLS Policies)

#### 5.1.1 Profiles (Users)

```sql
-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Super Admin sees all users
DROP POLICY IF EXISTS "Super Admin views all profiles" ON public.profiles;
CREATE POLICY "Super Admin views all profiles" 
  ON public.profiles FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's users
DROP POLICY IF EXISTS "Users view same tenant profiles" ON public.profiles;
CREATE POLICY "Users view same tenant profiles"
  ON public.profiles FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- Only admins can create users within their tenant
DROP POLICY IF EXISTS "Admins create users" ON public.profiles;
CREATE POLICY "Admins create users"
  ON public.profiles FOR INSERT
  WITH CHECK (
    public.can_manage_users() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- Users can update their own profile
DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid());

-- Admins can update their tenant's users
DROP POLICY IF EXISTS "Admins update tenant users" ON public.profiles;
CREATE POLICY "Admins update tenant users"
  ON public.profiles FOR UPDATE
  USING (
    public.can_manage_users() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );
```

#### 5.1.2 Products (Tenant-Scoped)

```sql
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Super Admin sees all products
DROP POLICY IF EXISTS "Super Admin views all products" ON public.products;
CREATE POLICY "Super Admin views all products"
  ON public.products FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's products
DROP POLICY IF EXISTS "Users view tenant products" ON public.products;
CREATE POLICY "Users view tenant products"
  ON public.products FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- Product managers can create products
DROP POLICY IF EXISTS "Managers create products" ON public.products;
CREATE POLICY "Managers create products"
  ON public.products FOR INSERT
  WITH CHECK (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- Product managers can update their tenant's products
DROP POLICY IF EXISTS "Managers update products" ON public.products;
CREATE POLICY "Managers update products"
  ON public.products FOR UPDATE
  USING (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );

-- Product managers can delete their tenant's products
DROP POLICY IF EXISTS "Managers delete products" ON public.products;
CREATE POLICY "Managers delete products"
  ON public.products FOR DELETE
  USING (
    public.can_manage_products() AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );
```

#### 5.1.3 Sales (Tenant-Scoped)

```sql
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

-- Super Admin sees all sales
DROP POLICY IF EXISTS "Super Admin views all sales" ON public.sales;
CREATE POLICY "Super Admin views all sales"
  ON public.sales FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's sales
DROP POLICY IF EXISTS "Users view tenant sales" ON public.sales;
CREATE POLICY "Users view tenant sales"
  ON public.sales FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- Cashiers and above can create sales
DROP POLICY IF EXISTS "Cashiers create sales" ON public.sales;
CREATE POLICY "Cashiers create sales"
  ON public.sales FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER')
    ) AND
    (public.is_super_admin() OR tenant_id = public.get_user_tenant_id())
  );
```

#### 5.1.4 Customers (Tenant-Scoped)

```sql
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Super Admin sees all customers
DROP POLICY IF EXISTS "Super Admin views all customers" ON public.customers;
CREATE POLICY "Super Admin views all customers"
  ON public.customers FOR SELECT
  USING (public.is_super_admin());

-- Vendor users see only their tenant's customers
DROP POLICY IF EXISTS "Users view tenant customers" ON public.customers;
CREATE POLICY "Users view tenant customers"
  ON public.customers FOR SELECT
  USING (tenant_id = public.get_user_tenant_id());

-- All authenticated users can manage customers within their tenant
DROP POLICY IF EXISTS "Users manage tenant customers" ON public.customers;
CREATE POLICY "Users manage tenant customers"
  ON public.customers FOR ALL
  USING (
    public.is_super_admin() OR tenant_id = public.get_user_tenant_id()
  )
  WITH CHECK (
    public.is_super_admin() OR tenant_id = public.get_user_tenant_id()
  );
```

#### 5.1.5 Tenants Table

```sql
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

-- Super Admin sees and manages all tenants
DROP POLICY IF EXISTS "Super Admin manages all tenants" ON public.tenants;
CREATE POLICY "Super Admin manages all tenants"
  ON public.tenants FOR ALL
  USING (public.is_super_admin());

-- Vendor admins can view and update their own tenant
DROP POLICY IF EXISTS "Vendor admin views own tenant" ON public.tenants;
CREATE POLICY "Vendor admin views own tenant"
  ON public.tenants FOR SELECT
  USING (id = public.get_user_tenant_id());

DROP POLICY IF EXISTS "Vendor admin updates own tenant" ON public.tenants;
CREATE POLICY "Vendor admin updates own tenant"
  ON public.tenants FOR UPDATE
  USING (id = public.get_user_tenant_id() AND public.is_vendor_admin());
```

### 5.2 Application-Level Isolation (Middleware)

#### Node.js Middleware for Tenant Resolution

```javascript
// middleware/tenantResolver.js
const { supabase } = require('../config/supabase');

/**
 * Middleware to resolve and attach tenant_id to request
 * Must run after authentication middleware
 */
async function resolveTenant(req, res, next) {
  try {
    const userId = req.user?.id; // From auth middleware
    
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Fetch user profile with tenant information
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('tenant_id, role, tenants!inner(id, name, type, is_active)')
      .eq('id', userId)
      .single();

    if (error || !profile) {
      return res.status(403).json({ error: 'User profile not found' });
    }

    // Check if tenant is active
    if (!profile.tenants.is_active) {
      return res.status(403).json({ error: 'Your account has been suspended. Please contact support.' });
    }

    // Attach tenant context to request
    req.tenant = {
      id: profile.tenant_id,
      name: profile.tenants.name,
      type: profile.tenants.type,
      isSuperAdmin: profile.role === 'SUPER_ADMIN'
    };

    req.userRole = profile.role;

    next();
  } catch (error) {
    console.error('Tenant resolution error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

module.exports = { resolveTenant };
```

#### Scoped Query Helper

```javascript
// utils/tenantQuery.js

/**
 * Apply tenant scoping to Supabase query
 * Super Admins bypass tenant filtering
 */
function scopeToTenant(query, req, tableName) {
  if (req.tenant.isSuperAdmin) {
    // Super Admin sees all data
    return query;
  }
  
  // Apply tenant filter for regular users
  return query.eq('tenant_id', req.tenant.id);
}

module.exports = { scopeToTenant };
```

### 5.3 Preventing Data Leakage

**Checklist:**
- ✅ All business tables have `tenant_id` column with NOT NULL constraint
- ✅ RLS policies enforce tenant isolation at database level
- ✅ Middleware validates tenant_id on every request
- ✅ Super Admin bypass requires explicit role check
- ✅ Foreign key constraints prevent cross-tenant references
- ✅ Composite unique constraints include `tenant_id` where applicable
- ✅ Audit logging tracks all cross-tenant actions

---

## 6. API Design & Access Rules

### 6.1 API Architecture

```
Client Request
    ↓
[Authentication Middleware]  ← Validate JWT, extract user ID
    ↓
[Tenant Resolution Middleware]  ← Resolve tenant_id, attach to req.tenant
    ↓
[Authorization Middleware]  ← Check user role permissions
    ↓
[Route Handler]  ← Apply tenant scoping to queries
    ↓
[Database (RLS Enforced)]
```

### 6.2 Example Protected Routes

```javascript
// routes/products.routes.js
const express = require('express');
const router = express.Router();
const { authenticate } = require('../middleware/auth');
const { resolveTenant } = require('../middleware/tenantResolver');
const { requireRole } = require('../middleware/authorization');
const productController = require('../controllers/product.controller');

// All routes require authentication and tenant resolution
router.use(authenticate);
router.use(resolveTenant);

// Public routes (within tenant)
router.get('/', productController.getAllProducts);  // Scoped to tenant
router.get('/:id', productController.getProduct);

// Protected routes (role-based)
router.post('/', 
  requireRole(['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER']),
  productController.createProduct
);

router.put('/:id',
  requireRole(['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER']),
  productController.updateProduct
);

router.delete('/:id',
  requireRole(['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'INVENTORY_MANAGER']),
  productController.deleteProduct
);

module.exports = router;
```

### 6.3 Controller Example with Tenant Scoping

```javascript
// controllers/product.controller.js
const { supabase } = require('../config/supabase');
const { scopeToTenant } = require('../utils/tenantQuery');

exports.getAllProducts = async (req, res) => {
  try {
    let query = supabase
      .from('products')
      .select('*')
      .eq('is_active', true);

    // Apply tenant scoping (Super Admin bypass handled here)
    query = scopeToTenant(query, req, 'products');

    const { data, error } = await query;

    if (error) throw error;

    res.json({
      success: true,
      data,
      tenant: req.tenant.name
    });
  } catch (error) {
    console.error('Error fetching products:', error);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
};

exports.createProduct = async (req, res) => {
  try {
    const productData = {
      ...req.body,
      tenant_id: req.tenant.id  // Force tenant_id from context
    };

    const { data, error } = await supabase
      .from('products')
      .insert([productData])
      .select()
      .single();

    if (error) throw error;

    res.status(201).json({
      success: true,
      data
    });
  } catch (error) {
    console.error('Error creating product:', error);
    res.status(500).json({ error: 'Failed to create product' });
  }
};
```

### 6.4 Super Admin Routes

```javascript
// routes/admin.routes.js
const express = require('express');
const router = express.Router();
const { authenticate } = require('../middleware/auth');
const { resolveTenant } = require('../middleware/tenantResolver');
const { requireSuperAdmin } = require('../middleware/authorization');
const adminController = require('../controllers/admin.controller');

// All routes require Super Admin role
router.use(authenticate);
router.use(resolveTenant);
router.use(requireSuperAdmin);

// Tenant Management
router.post('/tenants', adminController.createTenant);
router.get('/tenants', adminController.getAllTenants);
router.get('/tenants/:id', adminController.getTenant);
router.put('/tenants/:id', adminController.updateTenant);
router.delete('/tenants/:id', adminController.deleteTenant);
router.post('/tenants/:id/suspend', adminController.suspendTenant);
router.post('/tenants/:id/activate', adminController.activateTenant);

// Impersonation
router.post('/impersonate/:userId', adminController.impersonateUser);
router.post('/stop-impersonation', adminController.stopImpersonation);

// Analytics
router.get('/analytics/overview', adminController.getPlatformAnalytics);
router.get('/analytics/tenants/:id', adminController.getTenantAnalytics);

// Audit Logs
router.get('/audit-logs', adminController.getAuditLogs);

module.exports = router;
```

### 6.5 Authorization Middleware

```javascript
// middleware/authorization.js

/**
 * Require specific roles to access route
 */
function requireRole(allowedRoles) {
  return (req, res, next) => {
    if (!req.userRole) {
      return res.status(403).json({ error: 'Role information missing' });
    }

    if (!allowedRoles.includes(req.userRole)) {
      return res.status(403).json({ 
        error: 'Insufficient permissions',
        required: allowedRoles,
        current: req.userRole
      });
    }

    next();
  };
}

/**
 * Require Super Admin role
 */
function requireSuperAdmin(req, res, next) {
  if (req.userRole !== 'SUPER_ADMIN') {
    return res.status(403).json({ error: 'Super Admin access required' });
  }
  next();
}

/**
 * Require Vendor Admin role (within their tenant)
 */
function requireVendorAdmin(req, res, next) {
  if (!['SUPER_ADMIN', 'VENDOR_ADMIN'].includes(req.userRole)) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
}

module.exports = {
  requireRole,
  requireSuperAdmin,
  requireVendorAdmin
};
```

---

## 7. User Flows & Examples

### 7.1 Super Admin Onboards New Vendor

```
1. Super Admin logs in
   POST /api/auth/login
   { email: "superadmin@platform.com", password: "***" }
   
   Response: { token: "jwt_token", user: {...}, tenant: { type: "super" } }

2. Super Admin creates new vendor tenant
   POST /api/admin/tenants
   {
     "name": "Hamro Mart",
     "slug": "hamro-mart",
     "type": "vendor",
     "contact_email": "contact@hamromart.com",
     "contact_phone": "9841234567",
     "subscription_tier": "basic"
   }
   
   Response: { 
     success: true, 
     tenant: { id: "tenant-uuid-123", name: "Hamro Mart" }
   }

3. Super Admin creates Vendor Admin user
   POST /api/admin/tenants/tenant-uuid-123/users
   {
     "email": "hamromartadmin@gmail.com",
     "full_name": "Ram Sharma",
     "role": "VENDOR_ADMIN",
     "tenant_id": "tenant-uuid-123"
   }
   
   Response: { 
     success: true,
     user: { id: "user-uuid-456", email: "hamromartadmin@gmail.com" },
     credentials: { temporary_password: "temp123" }
   }

4. Vendor Admin receives welcome email with login link
```

### 7.2 Vendor Admin Manages Their Business

```
1. Vendor Admin logs in
   POST /api/auth/login
   { email: "hamromartadmin@gmail.com", password: "***" }
   
   Response: { 
     token: "jwt_token", 
     user: {...},
     tenant: { id: "tenant-uuid-123", name: "Hamro Mart", type: "vendor" }
   }

2. Vendor Admin adds a product
   POST /api/products
   {
     "name": "Dairy Milk Chocolate",
     "barcode": "8901063114418",
     "category_id": "cat-uuid-789",
     "cost_price": 50,
     "selling_price": 60,
     "stock_quantity": 100
   }
   
   Backend automatically adds: tenant_id = "tenant-uuid-123"
   
   Response: { success: true, data: { id: "product-uuid", ... } }

3. Vendor Admin creates a cashier user
   POST /api/users
   {
     "email": "hamromartcashier@gmail.com",
     "full_name": "Sita Devi",
     "role": "CASHIER"
   }
   
   Backend validates: user can only create users within their own tenant
   Backend automatically adds: tenant_id = "tenant-uuid-123"
   
   Response: { success: true, user: {...} }
```

### 7.3 Cashier Processes Sale

```
1. Cashier logs in
   POST /api/auth/login
   { email: "hamromartcashier@gmail.com", password: "***" }
   
   Response: { 
     token: "jwt_token",
     user: { role: "CASHIER" },
     tenant: { id: "tenant-uuid-123", name: "Hamro Mart" }
   }

2. Cashier fetches products
   GET /api/products
   
   Backend applies tenant filter: WHERE tenant_id = 'tenant-uuid-123'
   RLS policy also enforces tenant isolation
   
   Response: { data: [ { id: "product-uuid", name: "Dairy Milk", ... } ] }

3. Cashier processes sale
   POST /api/sales
   {
     "items": [
       { "product_id": "product-uuid", "quantity": 2, "unit_price": 60 }
     ],
     "payment_method": "cash",
     "total_amount": 120
   }
   
   Backend:
   - Validates tenant_id matches from token
   - Calls process_pos_sale RPC with tenant_id
   - Decrements stock for products within same tenant only
   
   Response: { 
     success: true,
     invoice_number: "INV-20260101-1234",
     sale_id: "sale-uuid"
   }
```

### 7.4 Super Admin Impersonates Vendor for Support

```
1. Super Admin wants to help debug an issue for "Hamro Mart"
   POST /api/admin/impersonate/user-uuid-456
   (user-uuid-456 is hamromartadmin@gmail.com)
   
   Backend:
   - Verifies requester is SUPER_ADMIN
   - Logs impersonation action in audit_logs
   - Issues new JWT with impersonated user context
   - Marks token with impersonation flag
   
   Response: {
     success: true,
     token: "impersonated_jwt_token",
     impersonating: {
       user: "Ram Sharma",
       tenant: "Hamro Mart"
     },
     original_admin: "Super Admin"
   }

2. Super Admin now sees data as if they are Vendor Admin
   GET /api/products
   
   Returns products for tenant-uuid-123 only
   
3. Super Admin stops impersonation
   POST /api/admin/stop-impersonation
   
   Response: { success: true, token: "original_super_admin_token" }
```

### 7.5 Multi-Vendor Scenario: Data Isolation

```
Scenario: Two vendors operating independently

Vendor A: Hamro Mart (tenant-uuid-123)
- Admin: hamromartadmin@gmail.com
- Product: Dairy Milk (product-uuid-A)

Vendor B: My Mart (tenant-uuid-456)
- Admin: mymartadmin@gmail.com
- Product: Dairy Milk (product-uuid-B)  ← Same product name, different tenant

Test 1: Vendor A admin tries to access Vendor B's products
  GET /api/products
  
  Backend applies filter: WHERE tenant_id = 'tenant-uuid-123'
  RLS policy enforces: tenant_id = get_user_tenant_id()
  
  Result: Only returns product-uuid-A ✅

Test 2: Vendor A cashier tries to sell Vendor B's product
  POST /api/sales
  {
    "items": [
      { "product_id": "product-uuid-B", ... }  ← Product from Vendor B
    ]
  }
  
  Backend:
  - Validates product exists in tenant
  - RLS policy on products table blocks access
  - Transaction fails
  
  Result: Error 403 - Product not found ✅

Test 3: Super Admin views all products
  GET /api/products
  (with SUPER_ADMIN role)
  
  Backend:
  - is_super_admin() returns TRUE
  - RLS policy allows: public.is_super_admin()
  - No tenant filter applied
  
  Result: Returns product-uuid-A AND product-uuid-B ✅
```

---

## 8. Security Considerations

### 8.1 Preventing Cross-Tenant Data Access

**Database Level:**
```sql
-- Example: Ensure foreign keys respect tenant boundaries
ALTER TABLE public.sale_items 
  ADD CONSTRAINT fk_sale_items_tenant_product 
  CHECK (
    NOT EXISTS (
      SELECT 1 FROM public.sales s, public.products p
      WHERE s.id = sale_id 
        AND p.id = product_id 
        AND s.tenant_id != p.tenant_id
    )
  );
```

**Application Level:**
```javascript
// Always validate tenant_id in mutations
async function createSale(req, res) {
  const { items, customer_id } = req.body;
  
  // Validate all products belong to user's tenant
  const productIds = items.map(item => item.product_id);
  
  const { data: products } = await supabase
    .from('products')
    .select('id')
    .in('id', productIds)
    .eq('tenant_id', req.tenant.id);
  
  if (products.length !== productIds.length) {
    return res.status(403).json({ 
      error: 'Invalid products: some items do not belong to your store' 
    });
  }
  
  // Validate customer belongs to tenant (if provided)
  if (customer_id) {
    const { data: customer } = await supabase
      .from('customers')
      .select('id')
      .eq('id', customer_id)
      .eq('tenant_id', req.tenant.id)
      .single();
    
    if (!customer) {
      return res.status(403).json({ error: 'Customer not found' });
    }
  }
  
  // Proceed with sale...
}
```

### 8.2 Impersonation Security

```javascript
// controllers/admin.controller.js
exports.impersonateUser = async (req, res) => {
  try {
    // 1. Verify requester is Super Admin
    if (req.userRole !== 'SUPER_ADMIN') {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const { userId } = req.params;

    // 2. Fetch target user profile
    const { data: targetUser, error } = await supabase
      .from('profiles')
      .select('*, tenants(*)')
      .eq('id', userId)
      .single();

    if (error || !targetUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    // 3. Log impersonation action
    await supabase.from('audit_logs').insert([{
      actor_id: req.user.id,
      actor_role: 'SUPER_ADMIN',
      tenant_id: targetUser.tenant_id,
      action: 'impersonate',
      entity_type: 'user',
      entity_id: userId,
      changes: {
        impersonated_user: targetUser.email,
        impersonated_tenant: targetUser.tenants.name
      },
      ip_address: req.ip,
      user_agent: req.headers['user-agent']
    }]);

    // 4. Generate impersonation token
    const impersonationToken = jwt.sign(
      {
        userId: targetUser.id,
        tenantId: targetUser.tenant_id,
        role: targetUser.role,
        impersonating: true,
        originalAdminId: req.user.id,
        expiresIn: '1h'  // Short-lived token
      },
      process.env.JWT_SECRET
    );

    res.json({
      success: true,
      token: impersonationToken,
      impersonating: {
        user: targetUser.full_name,
        email: targetUser.email,
        tenant: targetUser.tenants.name
      }
    });
  } catch (error) {
    console.error('Impersonation error:', error);
    res.status(500).json({ error: 'Impersonation failed' });
  }
};
```

### 8.3 Rate Limiting & DDoS Protection

```javascript
// middleware/rateLimiter.js
const rateLimit = require('express-rate-limit');

// Different rate limits per tenant tier
function getTenantRateLimiter(req) {
  const tier = req.tenant?.subscriptionTier || 'basic';
  
  const limits = {
    basic: { windowMs: 15 * 60 * 1000, max: 100 },     // 100 req/15min
    pro: { windowMs: 15 * 60 * 1000, max: 500 },       // 500 req/15min
    enterprise: { windowMs: 15 * 60 * 1000, max: 2000 } // 2000 req/15min
  };
  
  return limits[tier];
}

const tenantRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: (req) => getTenantRateLimiter(req).max,
  keyGenerator: (req) => `${req.tenant.id}:${req.ip}`,
  handler: (req, res) => {
    res.status(429).json({
      error: 'Too many requests',
      tenant: req.tenant.name,
      tier: req.tenant.subscriptionTier,
      retryAfter: '15 minutes'
    });
  }
});

module.exports = { tenantRateLimiter };
```

### 8.4 Audit Logging

```javascript
// middleware/auditLogger.js
const { supabase } = require('../config/supabase');

async function auditLog(req, res, next) {
  // Only log sensitive operations
  const auditableActions = ['POST', 'PUT', 'DELETE'];
  const auditablePaths = ['/api/users', '/api/tenants', '/api/settings'];
  
  const shouldAudit = auditableActions.includes(req.method) &&
    auditablePaths.some(path => req.path.startsWith(path));
  
  if (!shouldAudit) {
    return next();
  }

  // Store original send
  const originalSend = res.send;
  
  res.send = function(data) {
    // Log after response
    supabase.from('audit_logs').insert([{
      actor_id: req.user?.id,
      actor_role: req.userRole,
      tenant_id: req.tenant?.id,
      action: req.method.toLowerCase(),
      entity_type: req.path.split('/')[2], // e.g., 'users' from '/api/users'
      entity_id: req.params.id,
      changes: {
        request_body: req.body,
        response_status: res.statusCode
      },
      ip_address: req.ip,
      user_agent: req.headers['user-agent']
    }]).then(() => {
      // Continue with original send
      return originalSend.call(this, data);
    }).catch(err => {
      console.error('Audit logging failed:', err);
      return originalSend.call(this, data);
    });
  };

  next();
}

module.exports = { auditLog };
```

---

## 9. Scalability & Best Practices

### 9.1 Database Optimization

#### Indexing Strategy

```sql
-- Compound indexes for tenant-scoped queries
CREATE INDEX idx_products_tenant_active ON public.products(tenant_id, is_active);
CREATE INDEX idx_sales_tenant_date ON public.sales(tenant_id, created_at DESC);
CREATE INDEX idx_customers_tenant_phone ON public.customers(tenant_id, phone);

-- Partial indexes for common filters
CREATE INDEX idx_products_active_tenant ON public.products(tenant_id) 
  WHERE is_active = TRUE;

CREATE INDEX idx_sales_completed_tenant ON public.sales(tenant_id, created_at DESC) 
  WHERE status = 'completed';

-- Covering indexes for performance
CREATE INDEX idx_profiles_tenant_role_covering 
  ON public.profiles(tenant_id, role) 
  INCLUDE (full_name, email, is_active);
```

#### Query Optimization

```sql
-- Use materialized views for expensive aggregate queries
CREATE MATERIALIZED VIEW tenant_sales_summary AS
SELECT 
  tenant_id,
  DATE(created_at) as sale_date,
  COUNT(*) as total_transactions,
  SUM(total_amount) as total_revenue,
  SUM(discount_amount) as total_discounts
FROM public.sales
WHERE status = 'completed'
GROUP BY tenant_id, DATE(created_at);

CREATE UNIQUE INDEX idx_tenant_sales_summary 
  ON tenant_sales_summary(tenant_id, sale_date);

-- Refresh daily via cron
CREATE OR REPLACE FUNCTION refresh_tenant_sales_summary()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY tenant_sales_summary;
END;
$$ LANGUAGE plpgsql;
```

### 9.2 Caching Strategy

```javascript
// utils/cache.js
const Redis = require('redis');
const client = Redis.createClient();

async function getCachedTenantData(tenantId, key) {
  const cacheKey = `tenant:${tenantId}:${key}`;
  const cached = await client.get(cacheKey);
  
  if (cached) {
    return JSON.parse(cached);
  }
  
  return null;
}

async function setCachedTenantData(tenantId, key, data, ttl = 300) {
  const cacheKey = `tenant:${tenantId}:${key}`;
  await client.setEx(cacheKey, ttl, JSON.stringify(data));
}

async function invalidateTenantCache(tenantId, pattern = '*') {
  const keys = await client.keys(`tenant:${tenantId}:${pattern}`);
  if (keys.length > 0) {
    await client.del(keys);
  }
}

module.exports = {
  getCachedTenantData,
  setCachedTenantData,
  invalidateTenantCache
};
```

### 9.3 Background Jobs & Queue System

```javascript
// jobs/tenantJobs.js
const Queue = require('bull');
const { supabase } = require('../config/supabase');

// Separate queue per tenant to prevent noisy neighbors
function getTenantQueue(tenantId) {
  return new Queue(`tenant:${tenantId}:jobs`, {
    redis: process.env.REDIS_URL,
    limiter: {
      max: 10,      // Max 10 jobs
      duration: 1000 // per second per tenant
    }
  });
}

// Example: Generate daily reports
async function scheduleDaily ReportsForTenant(tenantId) {
  const queue = getTenantQueue(tenantId);
  
  await queue.add('generate_daily_report', {
    tenantId,
    reportDate: new Date().toISOString().split('T')[0]
  }, {
    repeat: {
      cron: '0 1 * * *'  // 1 AM daily
    }
  });
}

// Worker
queue.process('generate_daily_report', async (job) => {
  const { tenantId, reportDate } = job.data;
  
  const { data: sales } = await supabase
    .from('sales')
    .select('*')
    .eq('tenant_id', tenantId)
    .gte('created_at', `${reportDate}T00:00:00`)
    .lte('created_at', `${reportDate}T23:59:59`);
  
  // Generate and email report...
});
```

### 9.4 Monitoring & Alerts

```javascript
// middleware/monitoring.js
const prometheus = require('prom-client');

// Metrics per tenant
const requestDuration = new prometheus.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status', 'tenant_id']
});

const activeUsers = new prometheus.Gauge({
  name: 'active_users_by_tenant',
  help: 'Number of active users per tenant',
  labelNames: ['tenant_id', 'tenant_name']
});

function monitorRequest(req, res, next) {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    requestDuration
      .labels(req.method, req.route?.path || req.path, res.statusCode, req.tenant?.id || 'unknown')
      .observe(duration);
  });
  
  next();
}

module.exports = { monitorRequest };
```

### 9.5 Future Enhancements

1. **Multi-Region Support**
   - Geo-distributed databases (Supabase multi-region)
   - CDN for static assets
   - Latency-based routing

2. **Advanced Analytics**
   - Real-time dashboards per tenant
   - Predictive inventory management
   - Customer behavior analytics

3. **Subscription Management**
   - Stripe/Razorpay integration
   - Usage-based billing
   - Feature flags per tier

4. **Mobile Apps**
   - Tenant-branded mobile apps
   - Offline-first POS with sync
   - Push notifications

5. **API Ecosystem**
   - Public API for third-party integrations
   - Webhook system for events
   - OAuth2 for external apps

---

## 10. Migration Strategy

### 10.1 Migration Plan: Single-Tenant → Multi-Tenant

#### Phase 1: Schema Updates (Non-Breaking)

```sql
-- 1. Create tenants table
-- (see section 3.1.1)

-- 2. Add tenant_id columns (nullable initially)
ALTER TABLE public.products ADD COLUMN tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE public.customers ADD COLUMN tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE public.sales ADD COLUMN tenant_id UUID REFERENCES public.tenants(id);
-- ... repeat for all tables

-- 3. Create default tenant for existing data
INSERT INTO public.tenants (id, name, slug, type, subscription_status)
VALUES (
  'default-tenant-uuid',  -- Use a fixed UUID
  'Default Store',
  'default-store',
  'vendor',
  'active'
);

-- 4. Backfill tenant_id for existing data
UPDATE public.products SET tenant_id = 'default-tenant-uuid' WHERE tenant_id IS NULL;
UPDATE public.customers SET tenant_id = 'default-tenant-uuid' WHERE tenant_id IS NULL;
UPDATE public.sales SET tenant_id = 'default-tenant-uuid' WHERE tenant_id IS NULL;
-- ... repeat for all tables

-- 5. Make tenant_id NOT NULL
ALTER TABLE public.products ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.customers ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE public.sales ALTER COLUMN tenant_id SET NOT NULL;
-- ... repeat for all tables

-- 6. Update profiles table
ALTER TABLE public.profiles ADD COLUMN tenant_id UUID REFERENCES public.tenants(id);
UPDATE public.profiles SET tenant_id = 'default-tenant-uuid' WHERE tenant_id IS NULL;
ALTER TABLE public.profiles ALTER COLUMN tenant_id SET NOT NULL;

-- 7. Create indexes
-- (see section 9.1)
```

#### Phase 2: RLS Policy Migration

```sql
-- Step 1: Drop existing RLS policies
DROP POLICY IF EXISTS "Everyone views products" ON public.products;
DROP POLICY IF EXISTS "Admins/Managers manage products" ON public.products;
-- ... drop all existing policies

-- Step 2: Implement new multi-tenant policies
-- (see section 5.1)
```

#### Phase 3: Application Updates

```javascript
// Update all database queries to include tenant_id

// Before:
const { data } = await supabase.from('products').select('*');

// After:
const { data } = await supabase
  .from('products')
  .select('*')
  .eq('tenant_id', req.tenant.id);  // Explicit tenant scoping
```

#### Phase 4: Testing

```bash
# Test Cases:
1. Create new tenant
2. Create users in different tenants with same email domain
3. Verify data isolation (Vendor A cannot see Vendor B's data)
4. Test Super Admin access to all tenants
5. Test impersonation flow
6. Verify RLS policies prevent cross-tenant access
7. Load testing with multiple concurrent tenants
```

#### Phase 5: Deployment

```bash
1. Deploy schema changes (backward compatible)
2. Backfill tenant_id (idempotent script)
3. Deploy application with tenant-aware code
4. Enable RLS policies (gradual rollout)
5. Monitor for errors
6. Validate data integrity
```

### 10.2 Rollback Plan

```sql
-- Emergency rollback (if needed)

-- 1. Disable RLS temporarily
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
-- ... for all tables

-- 2. Revert to single-tenant mode
-- Keep tenant_id but ignore in queries

-- 3. Deploy previous application version

-- 4. Investigate and fix issues

-- 5. Re-attempt migration
```

---

## Appendix A: Complete Migration SQL Script

See: `migrations/011_multi_tenant_migration.sql`

## Appendix B: Environment Variables

```bash
# .env
DATABASE_URL=postgresql://user:pass@host:5432/dbname
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_KEY=your_service_key
JWT_SECRET=your_jwt_secret
REDIS_URL=redis://localhost:6379
NODE_ENV=production
```

## Appendix C: API Endpoint Reference

| Method | Endpoint | Role Required | Description |
|--------|----------|---------------|-------------|
| **Authentication** |
| POST | /api/auth/signup | Public | Register new user |
| POST | /api/auth/login | Public | Login |
| POST | /api/auth/logout | Authenticated | Logout |
| **Tenants (Super Admin Only)** |
| GET | /api/admin/tenants | SUPER_ADMIN | List all tenants |
| POST | /api/admin/tenants | SUPER_ADMIN | Create tenant |
| GET | /api/admin/tenants/:id | SUPER_ADMIN | Get tenant details |
| PUT | /api/admin/tenants/:id | SUPER_ADMIN | Update tenant |
| DELETE | /api/admin/tenants/:id | SUPER_ADMIN | Delete tenant |
| **Users** |
| GET | /api/users | VENDOR_ADMIN+ | List tenant users |
| POST | /api/users | VENDOR_ADMIN+ | Create user |
| PUT | /api/users/:id | VENDOR_ADMIN+ | Update user |
| DELETE | /api/users/:id | VENDOR_ADMIN+ | Delete user |
| **Products** |
| GET | /api/products | All | List products (scoped to tenant) |
| POST | /api/products | INVENTORY_MANAGER+ | Create product |
| PUT | /api/products/:id | INVENTORY_MANAGER+ | Update product |
| DELETE | /api/products/:id | INVENTORY_MANAGER+ | Delete product |
| **Sales** |
| GET | /api/sales | All | List sales (scoped to tenant) |
| POST | /api/sales | CASHIER+ | Create sale |
| GET | /api/sales/:id | All | Get sale details |
| **Customers** |
| GET | /api/customers | All | List customers |
| POST | /api/customers | CASHIER+ | Create customer |
| PUT | /api/customers/:id | VENDOR_MANAGER+ | Update customer |
| **Reports** |
| GET | /api/reports/daily | VENDOR_MANAGER+ | Daily sales report |
| GET | /api/reports/inventory | INVENTORY_MANAGER+ | Inventory report |
| GET | /api/admin/reports/platform | SUPER_ADMIN | Platform-wide analytics |

---

**End of Document**

For questions or clarifications, contact: architecture@yourplatform.com
