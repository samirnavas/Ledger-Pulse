-- ====================================================================
-- SUPABASE / POSTGRESQL REPAIR SCRIPT (PHASE 5)
-- ====================================================================

-- Step 1: Re-key / Assign owner_id to legacy records with NULL owner_id
DO $$
DECLARE
    v_first_user UUID;
BEGIN
    SELECT id INTO v_first_user FROM auth.users ORDER BY created_at ASC LIMIT 1;
    IF v_first_user IS NOT NULL THEN
        UPDATE public.companies SET owner_id = v_first_user WHERE owner_id IS NULL;
        UPDATE public.user_profiles SET owner_id = v_first_user WHERE owner_id IS NULL;
        UPDATE public.parties SET owner_id = v_first_user WHERE owner_id IS NULL;
        UPDATE public.ledger_entries SET owner_id = v_first_user WHERE owner_id IS NULL;
    END IF;
END $$;

-- Step 2: Clean orphan / non-JSON outbox entries
DELETE FROM public.sync_outbox
WHERE table_name NOT IN (
    'companies', 'user_profiles', 'accounts', 'parties', 'vouchers',
    'journals', 'journal_lines', 'ledger_entries', 'budgets',
    'recurring_rules', 'inventory_items', 'stock_ledger', 'audit_logs'
) OR payload IS NULL;

-- Step 3: Report void vs posted status discrepancies between vouchers and journals
SELECT v.id as voucher_id, v.status as voucher_status, j.id as journal_id, j.status as journal_status
FROM public.vouchers v
JOIN public.journals j ON j.voucher_id = v.id
WHERE v.status != j.status;

-- Step 4: Reset failed sync records back to pending
UPDATE public.sync_outbox
SET attempts = 0, last_error = NULL, next_attempt_at = NULL
WHERE last_error IS NOT NULL;

-- Step 5: Verify account balance differences from posted journal lines
SELECT
    a.id as account_id,
    a.name as account_name,
    a.current_balance_in_cents as cached_balance,
    COALESCE(SUM(jl.debit_in_cents - jl.credit_in_cents), 0) as computed_balance
FROM public.accounts a
LEFT JOIN public.journal_lines jl ON jl.account_id = a.id AND jl.is_deleted = false
LEFT JOIN public.journals j ON j.id = jl.journal_id AND j.status = 'posted' AND j.is_deleted = false
WHERE a.is_deleted = false
GROUP BY a.id, a.name, a.current_balance_in_cents
HAVING a.current_balance_in_cents != COALESCE(SUM(jl.debit_in_cents - jl.credit_in_cents), 0);
