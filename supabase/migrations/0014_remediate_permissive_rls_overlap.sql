-- Migration 0014: Remediate Permissive RLS Overlap and Restrict to Authenticated RBAC

-- 1. Drop dangerous legacy policies that grant {public} or unauthenticated access
DROP POLICY IF EXISTS "Company owner access" ON public.accounts;
DROP POLICY IF EXISTS "Company owner access" ON public.budgets;
DROP POLICY IF EXISTS "Company owner access" ON public.journal_lines;
DROP POLICY IF EXISTS "Company owner access" ON public.journals;
DROP POLICY IF EXISTS "Company owner access" ON public.ledger_entries;
DROP POLICY IF EXISTS "Company owner access" ON public.parties;
DROP POLICY IF EXISTS "Company owner access" ON public.recurring_rules;
DROP POLICY IF EXISTS "Company owner access" ON public.vouchers;
DROP POLICY IF EXISTS "Users can manage owned companies" ON public.companies;
DROP POLICY IF EXISTS "owner_isolation_user_profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can manage own profile" ON public.user_profiles;

-- 2. Drop redundant legacy owner_isolation policies that bypass shared_memberships RBAC
DROP POLICY IF EXISTS "owner_isolation_accounts" ON public.accounts;
DROP POLICY IF EXISTS "owner_isolation_budgets" ON public.budgets;
DROP POLICY IF EXISTS "owner_isolation_journal_lines" ON public.journal_lines;
DROP POLICY IF EXISTS "owner_isolation_journals" ON public.journals;
DROP POLICY IF EXISTS "owner_isolation_recurring_rules" ON public.recurring_rules;
DROP POLICY IF EXISTS "owner_isolation_vouchers" ON public.vouchers;
DROP POLICY IF EXISTS "owner_isolation_companies" ON public.companies;

-- 3. Harden is_company_owner function to prevent NULL owner bypass and require authentication
CREATE OR REPLACE FUNCTION public.is_company_owner(target_company_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT auth.uid() IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM public.companies 
      WHERE id = target_company_id 
        AND owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.shared_memberships
      WHERE profile_id = target_company_id
        AND account_id = auth.uid()
        AND role = 'owner'
    )
  );
$$;

-- 4. Secure user_profiles with authenticated-only policies matching auth.uid()
CREATE POLICY "usr_profile_select" ON public.user_profiles
  FOR SELECT TO authenticated
  USING (id = (auth.uid())::text);

CREATE POLICY "usr_profile_insert" ON public.user_profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = (auth.uid())::text);

CREATE POLICY "usr_profile_update" ON public.user_profiles
  FOR UPDATE TO authenticated
  USING (id = (auth.uid())::text)
  WITH CHECK (id = (auth.uid())::text);

-- 5. Add RBAC policies for legacy budgets and recurring_rules if present in ledger
DROP POLICY IF EXISTS "led_budgets_select" ON public.budgets;
DROP POLICY IF EXISTS "led_budgets_write" ON public.budgets;
CREATE POLICY "led_budgets_select" ON public.budgets
  FOR SELECT TO authenticated
  USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

CREATE POLICY "led_budgets_write" ON public.budgets
  FOR ALL TO authenticated
  USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']))
  WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']));

DROP POLICY IF EXISTS "led_recurring_select" ON public.recurring_rules;
DROP POLICY IF EXISTS "led_recurring_write" ON public.recurring_rules;
CREATE POLICY "led_recurring_select" ON public.recurring_rules
  FOR SELECT TO authenticated
  USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

CREATE POLICY "led_recurring_write" ON public.recurring_rules
  FOR ALL TO authenticated
  USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']))
  WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']));
