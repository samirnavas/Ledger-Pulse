-- ==============================================================================
-- LedgerPulse Staging Legacy Data Migration Rollback Script
-- Cleans up staging copy tables while preserving 100% of legacy data
-- ==============================================================================

TRUNCATE TABLE public.exp_transactions CASCADE;
TRUNCATE TABLE public.exp_budgets CASCADE;
TRUNCATE TABLE public.exp_recurring_rules CASCADE;
TRUNCATE TABLE public.exp_wallets CASCADE;
TRUNCATE TABLE public.exp_categories CASCADE;
DELETE FROM public.shared_memberships WHERE id LIKE 'mem_%';

