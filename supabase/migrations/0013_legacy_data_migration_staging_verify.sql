-- ==============================================================================
-- LedgerPulse Migration Reconciliation & Verification Check Script
-- Contract Version: v1.0.0-PROD-CONTRACT-20261106
-- ==============================================================================

SELECT 
    'companies' AS entity,
    count(*) AS total_rows,
    count(*) FILTER (WHERE mode = 'ledger') AS ledger_profiles,
    count(*) FILTER (WHERE mode = 'expense') AS expense_profiles,
    count(*) FILTER (WHERE mode NOT IN ('ledger', 'expense') OR mode IS NULL) AS invalid_modes
FROM public.companies

UNION ALL

SELECT 
    'shared_memberships' AS entity,
    count(*) AS total_rows,
    count(*) FILTER (WHERE role = 'owner') AS owner_memberships,
    0 AS metric_3,
    0 AS metric_4
FROM public.shared_memberships

UNION ALL

SELECT 
    'exp_wallets' AS entity,
    count(*) AS total_rows,
    COALESCE(sum(current_balance_in_cents), 0) AS total_balance_cents,
    0 AS metric_3,
    0 AS metric_4
FROM public.exp_wallets

UNION ALL

SELECT 
    'exp_transactions' AS entity,
    count(*) AS total_rows,
    count(*) FILTER (WHERE transaction_type = 'expense') AS expense_txns,
    count(*) FILTER (WHERE transaction_type = 'income') AS income_txns,
    count(*) FILTER (WHERE transaction_type = 'transfer') AS transfer_txns
FROM public.exp_transactions

UNION ALL

SELECT 
    'legacy_ledger_vouchers' AS entity,
    count(*) AS total_rows,
    count(*) FILTER (WHERE type IN ('sales', 'purchase')) AS commercial_vouchers,
    0 AS metric_3,
    0 AS metric_4
FROM public.vouchers;

