-- Migration: 039_rls_branch_isolation.sql
-- Purpose: Enforce branch-level isolation for users restricted to a specific branch

-- 1. Helper function to get current user's branch
CREATE OR REPLACE FUNCTION public.get_user_branch_id()
RETURNS UUID AS $$
    SELECT branch_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 2. Update Sales Table RLS
DROP POLICY IF EXISTS "View sales in own tenant" ON public.sales;
CREATE POLICY "View sales in own tenant and branch" ON public.sales
FOR SELECT USING (
    tenant_id = public.get_user_tenant_id()
    AND (
        -- If manager/admin (branch_id is null or they have a higher role), they see all sales in tenant.
        -- If restricted to a branch, they only see their branch sales.
        public.get_user_branch_id() IS NULL 
        OR branch_id = public.get_user_branch_id()
    )
);

-- Note: Other tables like products or customers might be shared across branches, 
-- but transactions (sales, orders, shifts) must be branch-isolated.
