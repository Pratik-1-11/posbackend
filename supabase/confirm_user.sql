-- Run this in your Supabase SQL Editor to confirm the admin email manually
UPDATE auth.users
SET email_confirmed_at = NOW(),
    updated_at = NOW()
WHERE email = 'admin@pos.com';
