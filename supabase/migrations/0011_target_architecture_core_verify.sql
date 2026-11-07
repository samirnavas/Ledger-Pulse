-- ====================================================================
-- MIGRATION 0011: VERIFICATION SCRIPT
-- ====================================================================

-- 1. Verify existence of Shared Governance and Expense tables
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'shared_memberships', 'shared_devices',
    'exp_wallets', 'exp_categories', 'exp_transactions', 'exp_budgets', 'exp_recurring_rules'
  )
ORDER BY tablename;

-- 2. Verify shared_profiles view is created with security_invoker
SELECT table_name, view_definition
FROM information_schema.views
WHERE table_schema = 'public' AND table_name = 'shared_profiles';

-- 3. Verify helper functions exist and have STABLE volatility
SELECT routine_name, routine_type, security_type, volatility
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('has_profile_role', 'get_profile_type', 'enforce_profile_type_immutability');

-- 4. Verify RLS is enabled on all target tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'shared_memberships', 'shared_devices',
    'exp_wallets', 'exp_categories', 'exp_transactions', 'exp_budgets', 'exp_recurring_rules',
    'companies', 'vouchers', 'journals', 'journal_lines', 'accounts'
  )
ORDER BY tablename;

