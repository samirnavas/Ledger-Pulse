-- ====================================================================
-- ROLLBACK SCRIPT FOR MIGRATION 0009: IDENTITY & SYNC HARDENING
-- ====================================================================

-- 1. Drop v2 sync mutation RPC function
DROP FUNCTION IF EXISTS public.sync_mutation_v2(TEXT, TEXT, TEXT, JSONB);

-- 2. Drop unique index
DROP INDEX IF EXISTS accounts_company_code_idx;
DROP INDEX IF EXISTS sync_outbox_table_record_idx;

-- 3. Drop owner policies
DROP POLICY IF EXISTS "owner_isolation_companies" ON public.companies;
DROP POLICY IF EXISTS "owner_isolation_user_profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "owner_isolation_parties" ON public.parties;
DROP POLICY IF EXISTS "owner_isolation_ledger_entries" ON public.ledger_entries;

-- 4. Disable RLS on domain tables
ALTER TABLE public.companies DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.parties DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries DISABLE ROW LEVEL SECURITY;
