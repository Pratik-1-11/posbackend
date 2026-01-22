# Multi-Tenant Migration Guide (Without Supabase CLI)

## Method 1: Using Supabase Dashboard (Easiest)

### Step 1: Backup Your Database

1. **Go to Supabase Dashboard**
   - Open: https://app.supabase.com
   - Select your project: `pos-mvp`

2. **Backup via SQL Editor**
   ```sql
   -- Copy this SQL and run in Supabase SQL Editor
   -- This creates a backup of your current schema
   
   -- First, check current data counts
   SELECT 'products' as table_name, COUNT(*) as count FROM products
   UNION ALL
   SELECT 'customers', COUNT(*) FROM customers
   UNION ALL
   SELECT 'sales', COUNT(*) FROM sales
   UNION ALL
   SELECT 'profiles', COUNT(*) FROM profiles;
   
   -- Save these numbers! You'll verify after migration.
   ```

3. **Export Data (Optional but Recommended)**
   - Go to: **Table Editor**
   - For each important table (products, customers, sales):
     - Click the table name
     - Click "..." menu → "Download as CSV"
   - Save these CSV files as backup

### Step 2: Run the Migration

#### Option A: Using Supabase SQL Editor (Recommended)

1. **Open SQL Editor**
   - In Supabase Dashboard: Click **SQL Editor** in sidebar
   - Click **New Query**

2. **Copy Migration SQL**
   - Open: `backend/supabase/migrations/011_multi_tenant_migration.sql`
   - Copy the ENTIRE file content

3. **Paste and Run**
   - Paste into SQL Editor
   - Click **Run** or press `Ctrl+Enter`
   - Wait for completion (may take 30-60 seconds)

4. **Check for Errors**
   - If you see green "Success" - you're done! ✅
   - If errors appear - copy the error message and we'll fix it

#### Option B: Using Table Editor (Manual, slower)

If SQL Editor doesn't work, we can create tables manually through Table Editor.

### Step 3: Verify Migration Success

Run this verification SQL in SQL Editor:

```sql
-- 1. Check tenants table created
SELECT COUNT(*) as tenant_count FROM public.tenants;
-- Should return: 2 (super tenant + default vendor)

-- 2. Check tenant_id added to all tables
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND column_name = 'tenant_id';
-- Should return multiple rows

-- 3. Check RLS enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND rowsecurity = true;
-- Should return multiple tables

-- 4. Verify data integrity
SELECT 'products' as table_name, COUNT(*) as count FROM products
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'sales', COUNT(*) FROM sales;
-- Numbers should match your backup counts!
```

### Step 4: Update Backend Code

Now let's update your Node.js backend to use the tenant-aware middleware.

## Method 2: Using Direct PostgreSQL Connection

If you have your database connection string:

### Step 1: Get Connection String

1. **From Supabase Dashboard:**
   - Go to: **Settings** → **Database**
   - Scroll to: **Connection string**
   - Copy the **Connection string** (URI format)
   - It looks like: `postgresql://postgres:[password]@[host]:5432/postgres`

2. **Or from your .env file:**
   ```bash
   # Check your backend/.env file
   DATABASE_URL=postgresql://...
   ```

### Step 2: Use psql (if installed)

If you have PostgreSQL tools installed:

```bash
# Backup
pg_dump "your_connection_string" > backup_20260101.sql

# Run migration
psql "your_connection_string" -f backend/supabase/migrations/011_multi_tenant_migration.sql
```

### Step 3: Alternative - Use pgAdmin or DBeaver

1. Download **pgAdmin** or **DBeaver** (free GUI tools)
2. Connect using your connection string
3. Open migration SQL file
4. Execute it

## Method 3: Node.js Script (Programmatic)

If you prefer, we can create a Node.js script to run the migration.

---

## What to Do If Migration Fails

### Common Errors and Solutions

**Error: "relation already exists"**
- Solution: Some tables already exist, this is OK
- The migration uses `CREATE TABLE IF NOT EXISTS`

**Error: "column already exists"**
- Solution: Run this cleanup first:
```sql
-- Check what needs to be added
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public';
```

**Error: "permission denied"**
- Solution: Make sure you're using the Service Role key, not anon key
- Check: Settings → API → service_role key

### Emergency Rollback

If something goes wrong:

```sql
-- 1. Disable RLS (temporary)
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales DISABLE ROW LEVEL SECURITY;

-- 2. Check your data is still there
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM sales;

-- 3. Contact me with the error message
```

---

## After Successful Migration

Run these queries to create your Super Admin user:

```sql
-- 1. Find your user ID from Supabase Auth
SELECT id, email FROM auth.users;

-- 2. Update your profile to be Super Admin
UPDATE public.profiles 
SET 
  tenant_id = '00000000-0000-0000-0000-000000000001',  -- Super tenant
  role = 'SUPER_ADMIN'
WHERE id = 'YOUR_USER_ID_HERE';  -- Replace with your actual user ID

-- 3. Verify
SELECT 
  p.email,
  p.role,
  t.name as tenant_name,
  t.type as tenant_type
FROM public.profiles p
JOIN public.tenants t ON p.tenant_id = t.id
WHERE p.id = 'YOUR_USER_ID_HERE';
```

---

## Need Help?

If you encounter any issues:
1. Copy the error message
2. Take a screenshot of the SQL Editor
3. Share with me and I'll help debug

**Pro Tip:** Do this in a staging environment first if possible!
