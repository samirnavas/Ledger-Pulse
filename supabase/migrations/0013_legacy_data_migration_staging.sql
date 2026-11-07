-- ==============================================================================
-- LedgerPulse Staging Legacy Data Migration Rehearsal Script
-- Contract Version: v1.0.0-PROD-CONTRACT-20261106
-- Non-Destructive Copy, Idempotent, Resumable, Zero-Loss
-- ==============================================================================

DO $$
DECLARE
    v_unknown_modes_count INT;
    v_orphan_vouchers_count INT;
    v_orphan_entries_count INT;
BEGIN
    RAISE NOTICE '>>> PHASE 1: PRE-FLIGHT VERIFICATION & INTEGRITY GUARDS';

    -- Guard 1: Detect unknown profile modes that cannot be deterministically mapped
    SELECT count(*) INTO v_unknown_modes_count
    FROM public.companies
    WHERE mode IS NOT NULL 
      AND mode NOT IN ('ledger', 'expense', 'expenseTracker');

    IF v_unknown_modes_count > 0 THEN
        RAISE EXCEPTION 'PRE-FLIGHT ABORT: Found % companies with unknown mode values.', v_unknown_modes_count;
    END IF;

    -- Guard 2: Detect orphan vouchers without valid company/profile
    SELECT count(*) INTO v_orphan_vouchers_count
    FROM public.vouchers v
    WHERE v.company_id NOT IN (SELECT id FROM public.companies);

    IF v_orphan_vouchers_count > 0 THEN
        RAISE EXCEPTION 'PRE-FLIGHT ABORT: Found % orphan vouchers referencing non-existent companies.', v_orphan_vouchers_count;
    END IF;

    -- Guard 3: Detect orphan ledger entries
    SELECT count(*) INTO v_orphan_entries_count
    FROM public.ledger_entries e
    WHERE e.company_id NOT IN (SELECT id FROM public.companies);

    IF v_orphan_entries_count > 0 THEN
        RAISE EXCEPTION 'PRE-FLIGHT ABORT: Found % orphan ledger entries referencing non-existent companies.', v_orphan_entries_count;
    END IF;

    RAISE NOTICE '>>> Pre-flight integrity checks PASSED. Baseline clean.';
END $$;

-- ------------------------------------------------------------------------------
-- 1. Deterministic Mode Backfill for NULL or Empty Modes
-- ------------------------------------------------------------------------------
UPDATE public.companies c
SET mode = CASE
    WHEN EXISTS (SELECT 1 FROM public.parties p WHERE p.company_id = c.id)
      OR EXISTS (SELECT 1 FROM public.inventory_items i WHERE i.company_id = c.id)
      OR EXISTS (SELECT 1 FROM public.vouchers v WHERE v.company_id = c.id AND v.type IN ('sales', 'purchase', 'contra', 'journal'))
    THEN 'ledger'
    WHEN EXISTS (SELECT 1 FROM public.vouchers v WHERE v.company_id = c.id AND v.type IN ('expense', 'income', 'transfer'))
    THEN 'expense'
    ELSE 'expense'
END
WHERE c.mode IS NULL OR c.mode = '';

-- Normalize 'expenseTracker' to 'expense'
UPDATE public.companies
SET mode = 'expense'
WHERE mode = 'expenseTracker';

-- ------------------------------------------------------------------------------
-- 2. Shared Memberships Migration (from companies.owner_id)
-- ------------------------------------------------------------------------------
INSERT INTO public.shared_memberships (
    id, profile_id, account_id, role, joined_at, updated_at
)
SELECT 
    'mem_' || substr(md5(c.id || '_' || c.owner_id), 1, 16),
    c.id,
    c.owner_id,
    'owner',
    COALESCE(c.created_at, NOW()),
    COALESCE(c.updated_at, NOW())
FROM public.companies c
WHERE c.owner_id IS NOT NULL
ON CONFLICT (profile_id, account_id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 3. Non-Destructive Copy to Expense Wallets (from accounts where kind = 'wallet')
-- ------------------------------------------------------------------------------
INSERT INTO public.exp_wallets (
    id, profile_id, name, wallet_type, currency_code,
    starting_balance_in_cents, current_balance_in_cents,
    is_archived, is_deleted, revision, created_at, updated_at
)
SELECT 
    a.id,
    a.company_id,
    a.name,
    CASE 
        WHEN a.code = 'CASH' OR a.name ILIKE '%cash%' THEN 'cash'
        WHEN a.code = 'BANK' OR a.name ILIKE '%bank%' THEN 'bank'
        ELSE 'digital_wallet'
    END,
    'INR',
    0,
    a.current_balance_in_cents,
    NOT a.is_active,
    a.is_deleted,
    a.revision,
    COALESCE(a.created_at, NOW()),
    COALESCE(a.updated_at, NOW())
FROM public.accounts a
JOIN public.companies c ON c.id = a.company_id
WHERE c.mode = 'expense'
  AND (a.kind = 'wallet' OR a.id LIKE '%_wallet_%' OR a.id LIKE '%_acc_wallet_%')
ON CONFLICT (id) DO UPDATE SET
    current_balance_in_cents = EXCLUDED.current_balance_in_cents,
    updated_at = EXCLUDED.updated_at;

-- ------------------------------------------------------------------------------
-- 4. Non-Destructive Copy to Expense Categories (from accounts where type in ('income', 'expense'))
-- ------------------------------------------------------------------------------
INSERT INTO public.exp_categories (
    id, profile_id, name, category_type,
    parent_category_id, is_system, is_deleted, revision, created_at, updated_at
)
SELECT 
    a.id,
    a.company_id,
    a.name,
    CASE WHEN a.type = 'income' THEN 'income' ELSE 'expense' END,
    a.parent_account_id,
    a.is_system,
    a.is_deleted,
    a.revision,
    COALESCE(a.created_at, NOW()),
    COALESCE(a.updated_at, NOW())
FROM public.accounts a
JOIN public.companies c ON c.id = a.company_id
WHERE c.mode = 'expense'
  AND (a.kind = 'category' OR a.type IN ('income', 'expense'))
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 5. Non-Destructive Copy to Expense Transactions (from vouchers: expense, income, transfer)
-- ------------------------------------------------------------------------------
INSERT INTO public.exp_transactions (
    id, profile_id, transaction_type, amount_in_cents,
    wallet_id, to_wallet_id, category_id,
    transaction_date, note, reference_number, receipt_photo_url,
    is_cleared, is_deleted, revision, created_at, updated_at
)
SELECT 
    v.id,
    v.company_id,
    v.type,
    v.total_amount_in_cents,
    COALESCE(v.wallet_account_id, (SELECT id FROM public.exp_wallets WHERE profile_id = v.company_id LIMIT 1), 'wal_default'),
    v.to_wallet_account_id,
    v.category_account_id,
    v.date,
    v.narration,
    v.reference_number,
    v.receipt_photo_url,
    true,
    v.is_deleted,
    v.revision,
    COALESCE(v.created_at, NOW()),
    COALESCE(v.updated_at, NOW())
FROM public.vouchers v
JOIN public.companies c ON c.id = v.company_id
WHERE c.mode = 'expense'
  AND v.type IN ('expense', 'income', 'transfer')
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 6. Non-Destructive Copy to Expense Budgets & Recurring Rules
-- ------------------------------------------------------------------------------
INSERT INTO public.exp_budgets (
    id, profile_id, category_id, period_type, amount_in_cents,
    start_date, is_deleted, revision, created_at, updated_at
)
SELECT 
    b.id, b.company_id, b.category_account_id, b.period_type, b.amount_in_cents,
    b.start_date, b.is_deleted, b.revision, COALESCE(b.created_at, NOW()), COALESCE(b.updated_at, NOW())
FROM public.budgets b
JOIN public.companies c ON c.id = b.company_id
WHERE c.mode = 'expense'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.exp_recurring_rules (
    id, profile_id, template_json, interval_type, interval_count,
    next_run_date, end_date, is_active, is_deleted, revision, created_at, updated_at
)
SELECT 
    r.id, r.company_id, r.template_json, r.interval_type, r.interval_count,
    r.next_run_date, r.end_date, r.is_active, r.is_deleted, r.revision, COALESCE(r.created_at, NOW()), COALESCE(r.updated_at, NOW())
FROM public.recurring_rules r
JOIN public.companies c ON c.id = r.company_id
WHERE c.mode = 'expense'
ON CONFLICT (id) DO NOTHING;

