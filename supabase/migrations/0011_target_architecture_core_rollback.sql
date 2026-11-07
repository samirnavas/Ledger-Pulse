-- ====================================================================
-- MIGRATION 0011: ROLLBACK SCRIPT
-- ====================================================================

-- Drop storage policies
DROP POLICY IF EXISTS "storage_tenant_select" ON storage.objects;
DROP POLICY IF EXISTS "storage_tenant_insert" ON storage.objects;
DROP POLICY IF EXISTS "storage_tenant_delete" ON storage.objects;

-- Drop dedicated Expense domain tables
DROP TABLE IF EXISTS public.exp_transactions CASCADE;
DROP TABLE IF EXISTS public.exp_budgets CASCADE;
DROP TABLE IF EXISTS public.exp_recurring_rules CASCADE;
DROP TABLE IF EXISTS public.exp_categories CASCADE;
DROP TABLE IF EXISTS public.exp_wallets CASCADE;

-- Drop Shared Governance tables and view
DROP VIEW IF EXISTS public.shared_profiles;
DROP TABLE IF EXISTS public.shared_devices CASCADE;
DROP TABLE IF EXISTS public.shared_memberships CASCADE;

-- Drop triggers and validation functions
DROP TRIGGER IF EXISTS trg_prevent_profile_type_mutation ON public.companies;
DROP FUNCTION IF EXISTS public.enforce_profile_type_immutability();
DROP FUNCTION IF EXISTS public.validate_profile_is_expense();
DROP FUNCTION IF EXISTS public.validate_profile_is_ledger();
DROP FUNCTION IF EXISTS public.has_profile_role(TEXT, TEXT[]);
DROP FUNCTION IF EXISTS public.get_profile_type(TEXT);

