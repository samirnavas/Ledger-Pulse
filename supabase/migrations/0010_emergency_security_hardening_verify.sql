-- ====================================================================
-- MIGRATION 0010: VERIFICATION SCRIPT
-- ====================================================================

-- 1. Verify that NO permissive "Allow public read-write" policies remain active
DO $$
DECLARE
    v_permissive_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_permissive_count
    FROM pg_policies
    WHERE schemaname = 'public'
      AND policyname LIKE '%Allow public read-write%';

    IF v_permissive_count > 0 THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: % permissive public policies still exist!', v_permissive_count;
    ELSE
        RAISE NOTICE 'SUCCESS: Zero permissive public policies detected.';
    END IF;
END $$;

-- 2. Verify that owner_isolation_companies does NOT contain "OR owner_id IS NULL"
DO $$
DECLARE
    v_qual TEXT;
BEGIN
    SELECT qual INTO v_qual
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'companies'
      AND policyname = 'owner_isolation_companies';

    IF v_qual ILIKE '%IS NULL%' THEN
        RAISE EXCEPTION 'VERIFICATION FAILED: owner_isolation_companies still contains NULL bypass clause: %', v_qual;
    ELSE
        RAISE NOTICE 'SUCCESS: owner_isolation_companies is strictly tenant-isolated.';
    END IF;
END $$;

-- 3. Verify all 13 core domain tables have RLS enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'companies', 'user_profiles', 'parties', 'ledger_entries',
    'accounts', 'vouchers', 'journals', 'journal_lines',
    'budgets', 'recurring_rules', 'inventory_items', 'stock_ledger', 'audit_logs'
  )
ORDER BY tablename;

