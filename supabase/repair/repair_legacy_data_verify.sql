-- ====================================================================
-- SUPABASE / POSTGRESQL REPAIR VERIFICATION SCRIPT (PHASE 5)
-- ====================================================================

-- 1. Check for companies with missing owner_id
SELECT count(*) as unowned_companies_count
FROM public.companies
WHERE owner_id IS NULL;

-- 2. Check for orphan outbox entries
SELECT count(*) as invalid_outbox_count
FROM public.sync_outbox
WHERE table_name NOT IN (
    'companies', 'user_profiles', 'accounts', 'parties', 'vouchers',
    'journals', 'journal_lines', 'ledger_entries', 'budgets',
    'recurring_rules', 'inventory_items', 'stock_ledger', 'audit_logs'
);

-- 3. Check for outbox entries in failed state
SELECT count(*) as failed_outbox_count
FROM public.sync_outbox
WHERE last_error IS NOT NULL;
