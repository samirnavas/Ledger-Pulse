-- ====================================================================
-- MIGRATION 0010: ROLLBACK SCRIPT
-- ====================================================================

-- Drop interim owner-isolated policies
DROP POLICY IF EXISTS "owner_isolation_accounts" ON public.accounts;
DROP POLICY IF EXISTS "owner_isolation_vouchers" ON public.vouchers;
DROP POLICY IF EXISTS "owner_isolation_journals" ON public.journals;
DROP POLICY IF EXISTS "owner_isolation_journal_lines" ON public.journal_lines;
DROP POLICY IF EXISTS "owner_isolation_budgets" ON public.budgets;
DROP POLICY IF EXISTS "owner_isolation_recurring_rules" ON public.recurring_rules;
DROP POLICY IF EXISTS "owner_isolation_inventory_items" ON public.inventory_items;
DROP POLICY IF EXISTS "owner_isolation_stock_ledger" ON public.stock_ledger;
DROP POLICY IF EXISTS "owner_isolation_audit_logs_select" ON public.audit_logs;
DROP POLICY IF EXISTS "owner_isolation_audit_logs_insert" ON public.audit_logs;

-- Revert companies policy back to migration 0009 state if required
DROP POLICY IF EXISTS "owner_isolation_companies" ON public.companies;
CREATE POLICY "owner_isolation_companies" ON public.companies
    FOR ALL USING (owner_id = auth.uid() OR owner_id IS NULL) WITH CHECK (owner_id = auth.uid());

