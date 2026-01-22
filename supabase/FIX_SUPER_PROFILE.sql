-- ==========================================
-- FIX SUPER ADMIN PROFILE (Corrected)
-- Run this in Supabase SQL Editor
-- ==========================================

-- 1. Insert or Update the profile for the new user
INSERT INTO public.profiles (
  id,
  email,
  full_name,
  role,
  tenant_id
)
VALUES (
  '86e1654c-ae05-4299-9376-953e03e3ac3c',  -- The User ID
  'superadmin@pos.com',
  'Platform Super Admin',
  'SUPER_ADMIN',
  '00000000-0000-0000-0000-000000000001'   -- Super Tenant ID
)
ON CONFLICT (id) DO UPDATE
SET 
  role = 'SUPER_ADMIN',
  tenant_id = '00000000-0000-0000-0000-000000000001',
  full_name = 'Platform Super Admin';

-- 2. Verify
SELECT * FROM public.profiles WHERE email = 'superadmin@pos.com';
