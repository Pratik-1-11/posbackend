# 🚀 Quick Start: Multi-Tenant Migration (Your Specific Setup)

Since you don't have Supabase CLI, here's the **easiest way** to do the migration:

---

## ✅ **Option 1: Supabase Dashboard (RECOMMENDED - No Tools Needed)**

### **Step 1: Backup (Just in Case)**

1. **Open Supabase Dashboard:**
   - Go to: https://app.supabase.com
   - Login with your account
   - Select project: **pos-mvp** (biocayznfcubjwwlymnq)

2. **Quick Backup (via SQL Editor):**
   - Click: **SQL Editor** (in left sidebar)
   - Click: **New Query**
   - Paste this and click **Run**:
   
   ```sql
   -- Check current data counts (save these numbers!)
   SELECT 'products' as table_name, COUNT(*) as count FROM products
   UNION ALL
   SELECT 'customers', COUNT(*) FROM customers
   UNION ALL
   SELECT 'sales', COUNT(*) FROM sales
   UNION ALL
   SELECT 'profiles', COUNT(*) FROM profiles
   UNION ALL
   SELECT 'expenses', COUNT(*) FROM expenses
   UNION ALL
   SELECT 'purchases', COUNT(*) FROM purchases;
   ```
   
   - **Write down these numbers!** You'll verify them after migration.

3. **Optional CSV Backup:**
   - Go to: **Table Editor**
   - For important tables (products, customers, sales):
     - Click table name → Click "..." menu → **Download as CSV**

---

### **Step 2: Run the Migration**

1. **Still in SQL Editor:**
   - Click: **New Query** (or create new tab)

2. **Open Migration File:**
   - In VS Code, open: `backend/supabase/migrations/011_multi_tenant_migration.sql`
   - Press `Ctrl+A` to select all
   - Press `Ctrl+C` to copy

3. **Paste and Execute:**
   - Back in Supabase SQL Editor
   - Paste the SQL (Ctrl+V)
   - Click **Run** button (or press Ctrl+Enter)
   - **Wait 30-60 seconds** for completion

4. **Check Result:**
   - ✅ If you see green "Success" message → **You're done!**
   - ❌ If you see errors → Copy error message and share with me

---

### **Step 3: Verify Migration Worked**

Run this in SQL Editor:

```sql
-- 1. Check tenants created
SELECT id, name, type FROM public.tenants;
-- Should show: Platform Admin (super) and Default Store (vendor)

-- 2. Check tenant_id added
SELECT table_name 
FROM information_schema.columns 
WHERE column_name = 'tenant_id' 
  AND table_schema = 'public';
-- Should show: products, customers, sales, etc.

-- 3. Verify data integrity
SELECT 'products' as table_name, COUNT(*) as count FROM products
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'sales', COUNT(*) FROM sales;
-- Compare with your backup numbers!
```

---

### **Step 4: Make Yourself Super Admin**

1. **Get Your User ID:**
   - Go to: **Authentication** → **Users**
   - Find your email
   - Click on your user
   - Copy the **User ID** (long UUID like: abc123-def456-...)

2. **Run This SQL:**
   ```sql
   -- Replace YOUR_USER_ID_HERE with your actual ID
   UPDATE public.profiles 
   SET 
     tenant_id = '00000000-0000-0000-0000-000000000001',  -- Super tenant
     role = 'SUPER_ADMIN'
   WHERE id = 'YOUR_USER_ID_HERE';
   
   -- Verify it worked
   SELECT email, role, full_name 
   FROM public.profiles 
   WHERE id = 'YOUR_USER_ID_HERE';
   ```

---

## ✅ **Option 2: Using Node.js Script (Alternative)**

If you prefer automation:

### **Run the Migration Helper Script:**

```bash
cd backend
node scripts/run-migration.js
```

This script will:
- ✅ Backup your data counts
- ✅ Check if migration is needed
- ✅ Guide you through the process
- ✅ Verify everything worked

**Note:** The script will still guide you to use Supabase Dashboard for the actual migration (safest method).

---

## ✅ **Option 3: Direct Database Connection (Advanced)**

If you want to use `psql` or database tools:

### **Get Your Connection String:**

1. **From Supabase Dashboard:**
   - **Settings** → **Database** → **Connection string**
   - Copy the URI format
   - Replace `[YOUR-PASSWORD]` with your database password

2. **Using psql (if installed):**
   ```bash
   # Backup
   pg_dump "postgresql://postgres:[password]@[host]:5432/postgres" > backup.sql
   
   # Run migration
   psql "postgresql://postgres:[password]@[host]:5432/postgres" \
     -f backend/supabase/migrations/011_multi_tenant_migration.sql
   ```

3. **Using DBeaver or pgAdmin:**
   - Install DBeaver (free): https://dbeaver.io/download/
   - Create new connection with your Supabase credentials
   - Open migration SQL file
   - Execute it

---

## 🎯 **What Happens After Migration?**

After running the migration successfully:

1. **Database Changes:**
   - ✅ New `tenants` table created
   - ✅ All business tables now have `tenant_id` column
   - ✅ Row-Level Security (RLS) policies enabled
   - ✅ Helper functions created for multi-tenancy

2. **Next Steps:**
   - Update your backend code to use tenant middleware
   - Test with different user roles
   - Create new vendor tenants

---

## ⚠️ **Troubleshooting**

### **Error: "relation already exists"**
- **Not a problem!** Some tables already exist
- Migration uses `CREATE TABLE IF NOT EXISTS`

### **Error: "column already exists"**
- **Also fine!** Migration uses `ADD COLUMN IF NOT EXISTS`

### **Error: "permission denied"**
- Make sure you're logged in as the project owner
- Or use Service Role key in API calls

### **Data looks wrong after migration:**
```sql
-- Quick check
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM customers;
SELECT COUNT(*) FROM sales;

-- Compare with your backup numbers
-- If numbers match, data is safe!
```

---

## 🆘 **If Something Goes Wrong**

### **Emergency Rollback:**

```sql
-- 1. Disable RLS temporarily
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;

-- 2. Check data is intact
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM customers;

-- 3. Contact me with error details
```

### **Need Help?**
- Share the error message
- Screenshot the SQL Editor
- I'll help you debug immediately

---

## 🎉 **Success Checklist**

After migration, you should have:

- ✅ Tenants table with 2 rows (Platform Admin + Default Store)
- ✅ All tables have `tenant_id` column
- ✅ Your user is `SUPER_ADMIN` role
- ✅ Data counts match your backup
- ✅ RLS policies enabled

---

## 📚 **Next: Update Backend Code**

Once migration is successful, update your Node.js backend:

1. **Add middleware to routes:**
   ```javascript
   // In your main app.js or routes
   const { authenticate } = require('./middleware/auth');
   const { resolveTenant } = require('./middleware/tenantResolver');
   
   app.use('/api', authenticate);
   app.use('/api', resolveTenant);
   ```

2. **Update controllers:**
   - See examples in: `backend/docs/examples/product.controller.tenant-aware.js`
   - Use `scopeToTenant()` helper for queries

3. **Test thoroughly** before going to production!

---

**Ready? Let's start with Option 1 (Supabase Dashboard) - it's the easiest!** 🚀
