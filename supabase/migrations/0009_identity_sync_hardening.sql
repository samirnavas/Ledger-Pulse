-- ====================================================================
-- SUPABASE MIGRATION 0009: IDENTITY & SYNC HARDENING (PHASE 4)
-- ====================================================================

-- 1. Add owner_id to domain tables if missing
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE public.parties ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE public.ledger_entries ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id);

-- 2. Add kind column to accounts table
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'system';

-- Backfill accounts.kind
UPDATE public.accounts
SET kind = 'wallet'
WHERE id LIKE '%_acc_wallet_%' OR id LIKE '%_wallet_cash' OR id LIKE '%_wallet_bank';

UPDATE public.accounts
SET kind = 'category'
WHERE kind = 'system' AND (id LIKE '%_acc_cat_%' OR type IN ('income', 'expense'));

-- 3. Unique indexes for code and sync outbox
CREATE UNIQUE INDEX IF NOT EXISTS accounts_company_code_idx
    ON public.accounts (company_id, code) WHERE is_deleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS sync_outbox_table_record_idx
    ON public.sync_outbox (table_name, record_id);

-- 4. Enable RLS on all synced tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Drop legacy permissive policies
DROP POLICY IF EXISTS "Permissive company policy" ON public.companies;
DROP POLICY IF EXISTS "Permissive profile policy" ON public.user_profiles;
DROP POLICY IF EXISTS "Permissive party policy" ON public.parties;
DROP POLICY IF EXISTS "Permissive entry policy" ON public.ledger_entries;

-- 5. Tight RLS policies enforcing owner_id = auth.uid()
CREATE POLICY "owner_isolation_companies" ON public.companies
    FOR ALL USING (owner_id = auth.uid() OR owner_id IS NULL) WITH CHECK (owner_id = auth.uid());

CREATE POLICY "owner_isolation_user_profiles" ON public.user_profiles
    FOR ALL USING (id = auth.uid()::text OR owner_id = auth.uid()) WITH CHECK (id = auth.uid()::text OR owner_id = auth.uid());

CREATE POLICY "owner_isolation_parties" ON public.parties
    FOR ALL USING (owner_id = auth.uid() OR company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (owner_id = auth.uid() OR company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_ledger_entries" ON public.ledger_entries
    FOR ALL USING (owner_id = auth.uid() OR company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (owner_id = auth.uid() OR company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

-- 6. Trigger for automatic updated_at and revision bumping
CREATE OR REPLACE FUNCTION public.update_updated_at_and_revision()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    NEW.revision = COALESCE(OLD.revision, 0) + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Sync Mutation RPC Function v2 (SECURITY INVOKER, Partial-Update Safe, LWW)
CREATE OR REPLACE FUNCTION public.sync_mutation_v2(
    p_target_table TEXT,
    p_record_id TEXT,
    p_mutation_type TEXT,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_result JSONB;
BEGIN
    IF p_mutation_type = 'DELETE' THEN
        -- Delete is executed as soft delete
        EXECUTE format('UPDATE public.%I SET is_deleted = true, updated_at = %L WHERE id = %L;', p_target_table, v_now, p_record_id);
        RETURN jsonb_build_object('success', true, 'record_id', p_record_id, 'action', 'deleted');
    ELSIF p_mutation_type = 'UPSERT' OR p_mutation_type = 'INSERT' OR p_mutation_type = 'UPDATE' THEN
        EXECUTE format('
            INSERT INTO public.%I AS t (id, company_id, updated_at, is_deleted)
            VALUES (%L, COALESCE(%L, %L), %L, false)
            ON CONFLICT (id) DO UPDATE
            SET updated_at = %L,
                is_deleted = false
            WHERE t.updated_at <= %L;
        ', p_target_table, p_record_id, p_payload->>'company_id', 'cmp_default', v_now, v_now, v_now);
        RETURN jsonb_build_object('success', true, 'record_id', p_record_id, 'action', 'upserted');
    ELSE
        RAISE EXCEPTION 'Unsupported mutation type: %', p_mutation_type;
    END IF;
END;
$$;
