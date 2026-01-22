-- ==========================================
-- SETUP SUPER ADMIN USER
-- Run this in Supabase SQL Editor
-- ==========================================

-- Step 1: Find your user ID and current profile
SELECT 
  p.id,
  p.email,
  p.full_name,
  p.role as current_role,
  t.name as current_tenant
FROM public.profiles p
LEFT JOIN public.tenants t ON p.tenant_id = t.id
ORDER BY p.created_at DESC;

-- Step 2: Copy your user ID from above, then run this:
-- Replace 'YOUR_USER_ID' with the actual ID from Step 1

UPDATE public.profiles 
SET 
  tenant_id = '00000000-0000-0000-0000-000000000001',  -- Super tenant
  role = 'SUPER_ADMIN'
WHERE email = 'superadmin@gmail.com';  -- Replace with your actual email

-- Step 3: Verify it worked
SELECT 
  p.email,
  p.full_name,
  p.role,
  t.name as tenant_name,
  t.type as tenant_type
FROM public.profiles p
JOIN public.tenants t ON p.tenant_id = t.id
WHERE p.role = 'SUPER_ADMIN';

-- You should see yourself as SUPER_ADMIN in "Platform Admin" tenant!
