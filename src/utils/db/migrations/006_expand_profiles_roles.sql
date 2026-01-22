-- Add more roles to profiles table
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check 
CHECK (role IN ('super_admin', 'branch_admin', 'cashier', 'inventory_manager', 'waiter', 'manager', 'admin'));

-- Also ensure we have a way to view email from auth.users
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email TEXT;
