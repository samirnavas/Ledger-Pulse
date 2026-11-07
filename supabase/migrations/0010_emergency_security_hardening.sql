-- ====================================================================
-- SUPABASE MIGRATION 0010: EMERGENCY SECURITY HARDENING & LEAK REMEDIATION
-- Target: LedgerPulse Supabase / PostgreSQL
-- Contract Version: v1.0.0-PROD-CONTRACT-20261106
-- ====================================================================

-- --------------------------------------------------------------------
-- STEP 1: DROP ALL 6 PERMISSIVE PUBLIC POLICIES FROM MIGRATION 0008
-- (These policies granted USING (true) WITH CHECK (true) to anon and authenticated)
-- --------------------------------------------------------------------
DROP POLICY IF EXISTS "Allow public read-write on accounts" ON public.accounts;
DROP POLICY IF EXISTS "Allow public read-write on vouchers" ON public.vouchers;
DROP POLICY IF EXISTS "Allow public read-write on journals" ON public.journals;
DROP POLICY IF EXISTS "Allow public read-write on journal_lines" ON public.journal_lines;
DROP POLICY IF EXISTS "Allow public read-write on budgets" ON public.budgets;
DROP POLICY IF EXISTS "Allow public read-write on recurring_rules" ON public.recurring_rules;

-- Also drop any other historical permissive policies if present
DROP POLICY IF EXISTS "Allow public read-write on companies" ON public.companies;
DROP POLICY IF EXISTS "Allow public read-write on sync_outbox" ON public.sync_outbox;
DROP POLICY IF EXISTS "Allow public read-write on ledger_entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "Allow public read-write on parties" ON public.parties;
DROP POLICY IF EXISTS "companies_delete_all" ON public.companies;
DROP POLICY IF EXISTS "companies_insert_all" ON public.companies;
DROP POLICY IF EXISTS "companies_select_all" ON public.companies;
DROP POLICY IF EXISTS "companies_update_all" ON public.companies;
DROP POLICY IF EXISTS "user_profiles_delete_all" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_insert_all" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_select_all" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_update_all" ON public.user_profiles;
DROP POLICY IF EXISTS "Permissive company policy" ON public.companies;
DROP POLICY IF EXISTS "Permissive profile policy" ON public.user_profiles;
DROP POLICY IF EXISTS "Permissive party policy" ON public.parties;
DROP POLICY IF EXISTS "Permissive entry policy" ON public.ledger_entries;

-- --------------------------------------------------------------------
-- STEP 2: REMOVE PERMISSIVE 'OR owner_id IS NULL' BYPASS FROM MIGRATION 0009
-- (Strictly lock down companies to authenticated owner)
-- --------------------------------------------------------------------
DROP POLICY IF EXISTS "owner_isolation_companies" ON public.companies;
CREATE POLICY "owner_isolation_companies" ON public.companies
    FOR ALL TO authenticated
    USING (owner_id = auth.uid())
    WITH CHECK (owner_id = auth.uid());

-- --------------------------------------------------------------------
-- STEP 3: ESTABLISH INTERIM OWNER-SCOPED POLICIES ON ALL FINANCIAL & INVENTORY TABLES
-- (Guarantees zero-trust data protection prior to multi-member expansion in 0011)
-- --------------------------------------------------------------------

-- 3.1 Accounts
DROP POLICY IF EXISTS "owner_isolation_accounts" ON public.accounts;
CREATE POLICY "owner_isolation_accounts" ON public.accounts
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 3.2 Vouchers
DROP POLICY IF EXISTS "owner_isolation_vouchers" ON public.vouchers;
CREATE POLICY "owner_isolation_vouchers" ON public.vouchers
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 3.3 Journals
DROP POLICY IF EXISTS "owner_isolation_journals" ON public.journals;
CREATE POLICY "owner_isolation_journals" ON public.journals
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 3.4 Journal Lines
DROP POLICY IF EXISTS "owner_isolation_journal_lines" ON public.journal_lines;
CREATE POLICY "owner_isolation_journal_lines" ON public.journal_lines
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 3.5 Budgets
DROP POLICY IF EXISTS "owner_isolation_budgets" ON public.budgets;
CREATE POLICY "owner_isolation_budgets" ON public.budgets
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 3.6 Recurring Rules
DROP POLICY IF EXISTS "owner_isolation_recurring_rules" ON public.recurring_rules;
CREATE POLICY "owner_isolation_recurring_rules" ON public.recurring_rules
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 3.7 Inventory Items, Stock Ledger, and Audit Logs (Conditional on table existence)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_items') THEN
        DROP POLICY IF EXISTS "owner_isolation_inventory_items" ON public.inventory_items;
        EXECUTE 'CREATE POLICY "owner_isolation_inventory_items" ON public.inventory_items FOR ALL TO authenticated USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid())) WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stock_ledger') THEN
        DROP POLICY IF EXISTS "owner_isolation_stock_ledger" ON public.stock_ledger;
        EXECUTE 'CREATE POLICY "owner_isolation_stock_ledger" ON public.stock_ledger FOR ALL TO authenticated USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid())) WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
        DROP POLICY IF EXISTS "owner_isolation_audit_logs_select" ON public.audit_logs;
        EXECUTE 'CREATE POLICY "owner_isolation_audit_logs_select" ON public.audit_logs FOR SELECT TO authenticated USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))';
        DROP POLICY IF EXISTS "owner_isolation_audit_logs_insert" ON public.audit_logs;
        EXECUTE 'CREATE POLICY "owner_isolation_audit_logs_insert" ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))';
    END IF;
END $$;

-- Ensure RLS is enabled on all tables
ALTER TABLE IF EXISTS public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.recurring_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.stock_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.audit_logs ENABLE ROW LEVEL SECURITY;

