-- ====================================================================
-- SUPABASE MIGRATION 0017: FIX COMPANIES & MEMBERSHIPS RLS POLICIES AND TRIGGER FUNCTIONS
-- Target: LedgerPulse Supabase / PostgreSQL
-- Purpose: Ensures authenticated company owners can directly SELECT, INSERT (with RETURNING),
--          and UPDATE their companies without failing self-referencing subqueries in has_profile_role,
--          and ensures domain triggers handle pending profile creation gracefully.
-- ====================================================================

-- 1. Update Companies Membership Select Policy to check owner_id directly
ALTER POLICY "companies_membership_select_policy" ON public.companies
    USING (owner_id = auth.uid() OR public.has_profile_role(id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

-- 2. Update Companies Membership Update Policy to check owner_id directly
ALTER POLICY "companies_membership_update_policy" ON public.companies
    USING (owner_id = auth.uid() OR public.has_profile_role(id, ARRAY['owner', 'admin']))
    WITH CHECK (owner_id = auth.uid() OR public.has_profile_role(id, ARRAY['owner', 'admin']));

-- 3. Update Shared Memberships Insert Policy to allow initial owner insertion
ALTER POLICY "memberships_insert_policy" ON public.shared_memberships
    WITH CHECK (
        (account_id = auth.uid() AND role = 'owner' AND EXISTS (SELECT 1 FROM public.companies c WHERE c.id = profile_id AND c.owner_id = auth.uid()))
        OR public.has_profile_role(profile_id, ARRAY['owner', 'admin'])
    );

-- 4. Update validate_profile_is_expense trigger function
CREATE OR REPLACE FUNCTION public.validate_profile_is_expense()
RETURNS TRIGGER AS $$
DECLARE
  v_mode text;
BEGIN
  IF NEW.profile_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT mode INTO v_mode FROM public.companies WHERE id = NEW.profile_id;
  IF v_mode IS NULL THEN
    RAISE EXCEPTION 'Domain Isolation Violation: Profile % does not exist in companies', NEW.profile_id;
  END IF;

  IF v_mode NOT IN ('expense', 'expenseTracker', 'expense_tracker') THEN
    RAISE EXCEPTION 'Domain Isolation Violation: Profile % has mode "%", but must be an "expense" profile', NEW.profile_id, v_mode;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Update validate_profile_is_ledger trigger function
CREATE OR REPLACE FUNCTION public.validate_profile_is_ledger()
RETURNS TRIGGER AS $$
DECLARE
  v_mode text;
BEGIN
  IF NEW.company_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT mode INTO v_mode FROM public.companies WHERE id = NEW.company_id;
  IF v_mode IS NULL THEN
    RAISE EXCEPTION 'Domain Isolation Violation: Company % does not exist in companies', NEW.company_id;
  END IF;

  IF v_mode NOT IN ('ledger', 'ledger_pulse', 'business', 'company') AND v_mode NOT IN ('expense', 'expenseTracker', 'expense_tracker') THEN
    RAISE EXCEPTION 'Domain Isolation Violation: Company % has mode "%", but must be a "ledger" profile', NEW.company_id, v_mode;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
