-- ====================================================================
-- SUPABASE MIGRATION 0011: TARGET ARCHITECTURE CORE SCHEMA & DOMAIN ISOLATION
-- Target: LedgerPulse Supabase / PostgreSQL
-- Contract Version: v1.0.0-PROD-CONTRACT-20261106
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. SHARED GOVERNANCE & IDENTITY EXTENSION
-- --------------------------------------------------------------------

-- 1.1 Shared Memberships Table (Multi-profile ownership & RBAC)
CREATE TABLE IF NOT EXISTS public.shared_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT shared_memberships_profile_account_uniq UNIQUE (profile_id, account_id)
);

CREATE INDEX IF NOT EXISTS idx_memberships_account_profile ON public.shared_memberships(account_id, profile_id);
CREATE INDEX IF NOT EXISTS idx_memberships_profile_role ON public.shared_memberships(profile_id, role);

-- Seed initial memberships from existing companies.owner_id
INSERT INTO public.shared_memberships (profile_id, account_id, role)
SELECT id, owner_id, 'owner'
FROM public.companies
WHERE owner_id IS NOT NULL
ON CONFLICT (profile_id, account_id) DO NOTHING;

-- 1.2 Shared Devices Table (Hardware client binding & license quota)
CREATE TABLE IF NOT EXISTS public.shared_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_uuid TEXT NOT NULL,
    device_name TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'windows', 'web', 'macos', 'linux')),
    push_token TEXT,
    last_sync_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT shared_devices_account_device_uniq UNIQUE (account_id, device_uuid)
);

CREATE INDEX IF NOT EXISTS idx_shared_devices_account_active ON public.shared_devices(account_id, is_active);

-- 1.3 Canonical View: shared_profiles over companies (Security Invoker)
CREATE OR REPLACE VIEW public.shared_profiles
WITH (security_invoker = true) AS
SELECT 
    id,
    name,
    legal_name,
    mode AS profile_type,
    owner_id,
    currency_code,
    gstin,
    state_code,
    dealer_type,
    address,
    email,
    phone_number,
    logo_url,
    signature_url,
    signatory_name,
    bank_name,
    bank_account_number,
    bank_ifsc,
    upi_id,
    is_cloud_sync_enabled,
    is_active,
    enabled_modules,
    revision,
    is_deleted,
    created_at,
    updated_at
FROM public.companies;

-- 1.4 Profile Type Immutability Trigger
CREATE OR REPLACE FUNCTION public.enforce_profile_type_immutability()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.mode IS DISTINCT FROM NEW.mode THEN
        RAISE EXCEPTION 'Profile type is immutable. Mutating mode from % to % is prohibited by contract v1.0.0.',
            OLD.mode, NEW.mode;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_profile_type_mutation ON public.companies;
CREATE TRIGGER trg_prevent_profile_type_mutation
BEFORE UPDATE ON public.companies
FOR EACH ROW
EXECUTE FUNCTION public.enforce_profile_type_immutability();


-- --------------------------------------------------------------------
-- 2. DEDICATED EXPENSE DOMAIN SCHEMA (STRICTLY SINGLE-ENTRY)
-- --------------------------------------------------------------------

-- 2.1 Expense Wallets
CREATE TABLE IF NOT EXISTS public.exp_wallets (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    wallet_type TEXT NOT NULL CHECK (wallet_type IN ('cash', 'bank', 'credit_card', 'digital_wallet', 'savings')),
    currency_code TEXT NOT NULL DEFAULT 'INR' CHECK (currency_code ~ '^[A-Z]{3}$'),
    starting_balance_in_cents BIGINT NOT NULL DEFAULT 0,
    current_balance_in_cents BIGINT NOT NULL DEFAULT 0,
    color_hex TEXT,
    icon_name TEXT,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exp_wallets_profile ON public.exp_wallets(profile_id) WHERE is_deleted = false;

-- 2.2 Expense Categories
CREATE TABLE IF NOT EXISTS public.exp_categories (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category_type TEXT NOT NULL CHECK (category_type IN ('expense', 'income')),
    parent_category_id TEXT REFERENCES public.exp_categories(id) ON DELETE SET NULL,
    icon_name TEXT,
    color_hex TEXT,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exp_categories_profile_type ON public.exp_categories(profile_id, category_type) WHERE is_deleted = false;

-- 2.3 Expense Transactions
CREATE TABLE IF NOT EXISTS public.exp_transactions (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('expense', 'income', 'transfer')),
    amount_in_cents BIGINT NOT NULL CHECK (amount_in_cents > 0),
    wallet_id TEXT NOT NULL REFERENCES public.exp_wallets(id) ON DELETE RESTRICT,
    to_wallet_id TEXT REFERENCES public.exp_wallets(id) ON DELETE RESTRICT,
    category_id TEXT REFERENCES public.exp_categories(id) ON DELETE RESTRICT,
    transaction_date TIMESTAMPTZ NOT NULL,
    note TEXT,
    payee_or_payer TEXT,
    reference_number TEXT,
    receipt_photo_url TEXT,
    is_cleared BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT exp_transactions_transfer_wallets_chk CHECK (
        (transaction_type = 'transfer' AND to_wallet_id IS NOT NULL AND to_wallet_id <> wallet_id)
        OR (transaction_type <> 'transfer' AND to_wallet_id IS NULL)
    ),
    CONSTRAINT exp_transactions_category_required_chk CHECK (
        (transaction_type IN ('expense', 'income') AND category_id IS NOT NULL)
        OR (transaction_type = 'transfer')
    )
);

CREATE INDEX IF NOT EXISTS idx_exp_txns_profile_date ON public.exp_transactions(profile_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_exp_txns_wallet ON public.exp_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_exp_txns_category ON public.exp_transactions(category_id);
CREATE INDEX IF NOT EXISTS idx_exp_txns_profile_updated ON public.exp_transactions(profile_id, updated_at);

-- 2.4 Expense Budgets
CREATE TABLE IF NOT EXISTS public.exp_budgets (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    category_id TEXT NOT NULL REFERENCES public.exp_categories(id) ON DELETE CASCADE,
    period_type TEXT NOT NULL CHECK (period_type IN ('monthly', 'quarterly', 'yearly')),
    amount_in_cents BIGINT NOT NULL CHECK (amount_in_cents >= 0),
    start_date TIMESTAMPTZ NOT NULL,
    rollover_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exp_budgets_profile_category ON public.exp_budgets(profile_id, category_id) WHERE is_deleted = false;

-- 2.5 Expense Recurring Rules
CREATE TABLE IF NOT EXISTS public.exp_recurring_rules (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    template_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    interval_type TEXT NOT NULL CHECK (interval_type IN ('daily', 'weekly', 'monthly', 'yearly')),
    interval_count INTEGER NOT NULL DEFAULT 1 CHECK (interval_count > 0),
    next_run_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exp_recurring_rules_profile_next ON public.exp_recurring_rules(profile_id, next_run_date) WHERE is_active = true AND is_deleted = false;


-- --------------------------------------------------------------------
-- 3. DOMAIN ISOLATION TRIGGERS (EXPENSE VS LEDGER VALIDATION)
-- --------------------------------------------------------------------

-- 3.1 Validate Expense Domain Partition
CREATE OR REPLACE FUNCTION public.validate_profile_is_expense()
RETURNS TRIGGER AS $$
DECLARE
    v_mode TEXT;
BEGIN
    SELECT mode INTO v_mode FROM public.companies WHERE id = NEW.profile_id;
    IF v_mode IS NULL OR v_mode NOT IN ('expense', 'expenseTracker') THEN
        RAISE EXCEPTION 'Domain Isolation Violation: Profile % has mode "%", but must be an "expense" profile to store records in %',
            NEW.profile_id, v_mode, TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql STABLE;

DROP TRIGGER IF EXISTS trg_val_exp_wallets ON public.exp_wallets;
CREATE TRIGGER trg_val_exp_wallets BEFORE INSERT OR UPDATE OF profile_id ON public.exp_wallets FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_expense();

DROP TRIGGER IF EXISTS trg_val_exp_categories ON public.exp_categories;
CREATE TRIGGER trg_val_exp_categories BEFORE INSERT OR UPDATE OF profile_id ON public.exp_categories FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_expense();

DROP TRIGGER IF EXISTS trg_val_exp_transactions ON public.exp_transactions;
CREATE TRIGGER trg_val_exp_transactions BEFORE INSERT OR UPDATE OF profile_id ON public.exp_transactions FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_expense();

DROP TRIGGER IF EXISTS trg_val_exp_budgets ON public.exp_budgets;
CREATE TRIGGER trg_val_exp_budgets BEFORE INSERT OR UPDATE OF profile_id ON public.exp_budgets FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_expense();

DROP TRIGGER IF EXISTS trg_val_exp_recurring ON public.exp_recurring_rules;
CREATE TRIGGER trg_val_exp_recurring BEFORE INSERT OR UPDATE OF profile_id ON public.exp_recurring_rules FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_expense();


-- 3.2 Validate Ledger Domain Partition
CREATE OR REPLACE FUNCTION public.validate_profile_is_ledger()
RETURNS TRIGGER AS $$
DECLARE
    v_mode TEXT;
BEGIN
    SELECT mode INTO v_mode FROM public.companies WHERE id = NEW.company_id;
    IF v_mode IS NULL OR v_mode <> 'ledger' THEN
        RAISE EXCEPTION 'Domain Isolation Violation: Company % has mode "%", but must be a "ledger" profile to store records in %',
            NEW.company_id, v_mode, TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql STABLE;

DROP TRIGGER IF EXISTS trg_val_led_vouchers ON public.vouchers;
CREATE TRIGGER trg_val_led_vouchers BEFORE INSERT OR UPDATE OF company_id ON public.vouchers FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_ledger();

DROP TRIGGER IF EXISTS trg_val_led_journals ON public.journals;
CREATE TRIGGER trg_val_led_journals BEFORE INSERT OR UPDATE OF company_id ON public.journals FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_ledger();

DROP TRIGGER IF EXISTS trg_val_led_journal_lines ON public.journal_lines;
CREATE TRIGGER trg_val_led_journal_lines BEFORE INSERT OR UPDATE OF company_id ON public.journal_lines FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_ledger();

DROP TRIGGER IF EXISTS trg_val_led_parties ON public.parties;
CREATE TRIGGER trg_val_led_parties BEFORE INSERT OR UPDATE OF company_id ON public.parties FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_ledger();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_items') THEN
        DROP TRIGGER IF EXISTS trg_val_led_inventory_items ON public.inventory_items;
        CREATE TRIGGER trg_val_led_inventory_items BEFORE INSERT OR UPDATE OF company_id ON public.inventory_items FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_ledger();
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stock_ledger') THEN
        DROP TRIGGER IF EXISTS trg_val_led_stock_ledger ON public.stock_ledger;
        CREATE TRIGGER trg_val_led_stock_ledger BEFORE INSERT OR UPDATE OF company_id ON public.stock_ledger FOR EACH ROW EXECUTE FUNCTION public.validate_profile_is_ledger();
    END IF;
END $$;


-- --------------------------------------------------------------------
-- 4. HIGH-PERFORMANCE RLS HELPER FUNCTIONS
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.has_profile_role(p_profile_id TEXT, p_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.companies c
        WHERE c.id = p_profile_id AND c.owner_id = auth.uid()
        UNION ALL
        SELECT 1 FROM public.shared_memberships m
        WHERE m.profile_id = p_profile_id
          AND m.account_id = auth.uid()
          AND m.role = ANY(p_roles)
    );
$$;

CREATE OR REPLACE FUNCTION public.get_profile_type(p_profile_id TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT mode FROM public.companies WHERE id = p_profile_id;
$$;


-- --------------------------------------------------------------------
-- 5. TARGET ROW LEVEL SECURITY (RLS) POLICIES
-- --------------------------------------------------------------------

-- Enable RLS on all newly added tables
ALTER TABLE public.shared_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exp_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exp_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exp_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exp_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exp_recurring_rules ENABLE ROW LEVEL SECURITY;

-- 5.1 Shared Memberships Policies
DROP POLICY IF EXISTS "memberships_select_policy" ON public.shared_memberships;
CREATE POLICY "memberships_select_policy" ON public.shared_memberships
    FOR SELECT TO authenticated
    USING (account_id = auth.uid() OR public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

DROP POLICY IF EXISTS "memberships_insert_policy" ON public.shared_memberships;
CREATE POLICY "memberships_insert_policy" ON public.shared_memberships
    FOR INSERT TO authenticated
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

DROP POLICY IF EXISTS "memberships_update_policy" ON public.shared_memberships;
CREATE POLICY "memberships_update_policy" ON public.shared_memberships
    FOR UPDATE TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

DROP POLICY IF EXISTS "memberships_delete_policy" ON public.shared_memberships;
CREATE POLICY "memberships_delete_policy" ON public.shared_memberships
    FOR DELETE TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner']) OR account_id = auth.uid());

-- 5.2 Shared Devices Policies
DROP POLICY IF EXISTS "devices_isolation_policy" ON public.shared_devices;
CREATE POLICY "devices_isolation_policy" ON public.shared_devices
    FOR ALL TO authenticated
    USING (account_id = auth.uid())
    WITH CHECK (account_id = auth.uid());

-- 5.3 Companies / Shared Profiles Membership Policies
DROP POLICY IF EXISTS "owner_isolation_companies" ON public.companies;
DROP POLICY IF EXISTS "companies_membership_select_policy" ON public.companies;
CREATE POLICY "companies_membership_select_policy" ON public.companies
    FOR SELECT TO authenticated
    USING (public.has_profile_role(id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

DROP POLICY IF EXISTS "companies_insert_policy" ON public.companies;
CREATE POLICY "companies_insert_policy" ON public.companies
    FOR INSERT TO authenticated
    WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS "companies_membership_update_policy" ON public.companies;
CREATE POLICY "companies_membership_update_policy" ON public.companies
    FOR UPDATE TO authenticated
    USING (public.has_profile_role(id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(id, ARRAY['owner', 'admin']));

DROP POLICY IF EXISTS "companies_delete_policy" ON public.companies;
CREATE POLICY "companies_delete_policy" ON public.companies
    FOR DELETE TO authenticated
    USING (owner_id = auth.uid());

-- 5.4 Dedicated Expense Domain Policies
-- Wallets
DROP POLICY IF EXISTS "exp_wallets_select" ON public.exp_wallets;
CREATE POLICY "exp_wallets_select" ON public.exp_wallets FOR SELECT TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin', 'viewer']));

DROP POLICY IF EXISTS "exp_wallets_write" ON public.exp_wallets;
CREATE POLICY "exp_wallets_write" ON public.exp_wallets FOR ALL TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

-- Categories
DROP POLICY IF EXISTS "exp_categories_select" ON public.exp_categories;
CREATE POLICY "exp_categories_select" ON public.exp_categories FOR SELECT TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin', 'viewer']));

DROP POLICY IF EXISTS "exp_categories_write" ON public.exp_categories;
CREATE POLICY "exp_categories_write" ON public.exp_categories FOR ALL TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

-- Transactions
DROP POLICY IF EXISTS "exp_transactions_select" ON public.exp_transactions;
CREATE POLICY "exp_transactions_select" ON public.exp_transactions FOR SELECT TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin', 'viewer']));

DROP POLICY IF EXISTS "exp_transactions_write" ON public.exp_transactions;
CREATE POLICY "exp_transactions_write" ON public.exp_transactions FOR ALL TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

-- Budgets
DROP POLICY IF EXISTS "exp_budgets_select" ON public.exp_budgets;
CREATE POLICY "exp_budgets_select" ON public.exp_budgets FOR SELECT TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin', 'viewer']));

DROP POLICY IF EXISTS "exp_budgets_write" ON public.exp_budgets;
CREATE POLICY "exp_budgets_write" ON public.exp_budgets FOR ALL TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

-- Recurring Rules
DROP POLICY IF EXISTS "exp_recurring_select" ON public.exp_recurring_rules;
CREATE POLICY "exp_recurring_select" ON public.exp_recurring_rules FOR SELECT TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin', 'viewer']));

DROP POLICY IF EXISTS "exp_recurring_write" ON public.exp_recurring_rules;
CREATE POLICY "exp_recurring_write" ON public.exp_recurring_rules FOR ALL TO authenticated
    USING (public.has_profile_role(profile_id, ARRAY['owner', 'admin']))
    WITH CHECK (public.has_profile_role(profile_id, ARRAY['owner', 'admin']));

-- 5.5 Business Ledger Domain Role-Based Policies
-- Vouchers
DROP POLICY IF EXISTS "owner_isolation_vouchers" ON public.vouchers;
CREATE POLICY "led_vouchers_select" ON public.vouchers FOR SELECT TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

CREATE POLICY "led_vouchers_insert" ON public.vouchers FOR INSERT TO authenticated
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry']));

CREATE POLICY "led_vouchers_update" ON public.vouchers FOR UPDATE TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager']))
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager']));

CREATE POLICY "led_vouchers_delete" ON public.vouchers FOR DELETE TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin']));

-- Journals
DROP POLICY IF EXISTS "owner_isolation_journals" ON public.journals;
CREATE POLICY "led_journals_select" ON public.journals FOR SELECT TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'viewer']));

CREATE POLICY "led_journals_write" ON public.journals FOR ALL TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']))
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']));

-- Journal Lines
DROP POLICY IF EXISTS "owner_isolation_journal_lines" ON public.journal_lines;
CREATE POLICY "led_journal_lines_select" ON public.journal_lines FOR SELECT TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'viewer']));

CREATE POLICY "led_journal_lines_write" ON public.journal_lines FOR ALL TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']))
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']));

-- Accounts
DROP POLICY IF EXISTS "owner_isolation_accounts" ON public.accounts;
CREATE POLICY "led_accounts_select" ON public.accounts FOR SELECT TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

CREATE POLICY "led_accounts_write" ON public.accounts FOR ALL TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']))
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant']));

-- Parties
DROP POLICY IF EXISTS "owner_isolation_parties" ON public.parties;
CREATE POLICY "led_parties_select" ON public.parties FOR SELECT TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

CREATE POLICY "led_parties_write" ON public.parties FOR ALL TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry']))
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry']));

-- Ledger Entries (Single-entry customer/vendor credit subledger)
DROP POLICY IF EXISTS "owner_isolation_ledger_entries" ON public.ledger_entries;
CREATE POLICY "led_entries_select" ON public.ledger_entries FOR SELECT TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer']));

CREATE POLICY "led_entries_write" ON public.ledger_entries FOR ALL TO authenticated
    USING (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry']))
    WITH CHECK (public.has_profile_role(company_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry']));

-- 5.6 Optional / Future Tables (Conditional on table existence)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_items') THEN
        DROP POLICY IF EXISTS "owner_isolation_inventory_items" ON public.inventory_items;
        DROP POLICY IF EXISTS "led_inventory_select" ON public.inventory_items;
        DROP POLICY IF EXISTS "led_inventory_write" ON public.inventory_items;
        EXECUTE 'CREATE POLICY "led_inventory_select" ON public.inventory_items FOR SELECT TO authenticated USING (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''accountant'', ''manager'', ''data_entry'', ''viewer'']))';
        EXECUTE 'CREATE POLICY "led_inventory_write" ON public.inventory_items FOR ALL TO authenticated USING (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''manager''])) WITH CHECK (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''manager'']))';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stock_ledger') THEN
        DROP POLICY IF EXISTS "owner_isolation_stock_ledger" ON public.stock_ledger;
        DROP POLICY IF EXISTS "led_stock_ledger_select" ON public.stock_ledger;
        DROP POLICY IF EXISTS "led_stock_ledger_write" ON public.stock_ledger;
        EXECUTE 'CREATE POLICY "led_stock_ledger_select" ON public.stock_ledger FOR SELECT TO authenticated USING (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''accountant'', ''manager'', ''viewer'']))';
        EXECUTE 'CREATE POLICY "led_stock_ledger_write" ON public.stock_ledger FOR ALL TO authenticated USING (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''manager''])) WITH CHECK (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''manager'']))';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
        DROP POLICY IF EXISTS "owner_isolation_audit_logs_select" ON public.audit_logs;
        DROP POLICY IF EXISTS "owner_isolation_audit_logs_insert" ON public.audit_logs;
        DROP POLICY IF EXISTS "led_audit_logs_select" ON public.audit_logs;
        DROP POLICY IF EXISTS "led_audit_logs_insert" ON public.audit_logs;
        EXECUTE 'CREATE POLICY "led_audit_logs_select" ON public.audit_logs FOR SELECT TO authenticated USING (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''accountant'']))';
        EXECUTE 'CREATE POLICY "led_audit_logs_insert" ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (public.has_profile_role(company_id, ARRAY[''owner'', ''admin'', ''accountant'', ''manager'', ''data_entry'']))';
    END IF;
END $$;


-- --------------------------------------------------------------------
-- 6. REVISION BUMPING TRIGGERS FOR ALL NEW TABLES
-- --------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_rev_shared_memberships ON public.shared_memberships;
CREATE TRIGGER trg_rev_shared_memberships BEFORE UPDATE ON public.shared_memberships FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();

DROP TRIGGER IF EXISTS trg_rev_shared_devices ON public.shared_devices;
CREATE TRIGGER trg_rev_shared_devices BEFORE UPDATE ON public.shared_devices FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();

DROP TRIGGER IF EXISTS trg_rev_exp_wallets ON public.exp_wallets;
CREATE TRIGGER trg_rev_exp_wallets BEFORE UPDATE ON public.exp_wallets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();

DROP TRIGGER IF EXISTS trg_rev_exp_categories ON public.exp_categories;
CREATE TRIGGER trg_rev_exp_categories BEFORE UPDATE ON public.exp_categories FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();

DROP TRIGGER IF EXISTS trg_rev_exp_transactions ON public.exp_transactions;
CREATE TRIGGER trg_rev_exp_transactions BEFORE UPDATE ON public.exp_transactions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();

DROP TRIGGER IF EXISTS trg_rev_exp_budgets ON public.exp_budgets;
CREATE TRIGGER trg_rev_exp_budgets BEFORE UPDATE ON public.exp_budgets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();

DROP TRIGGER IF EXISTS trg_rev_exp_recurring ON public.exp_recurring_rules;
CREATE TRIGGER trg_rev_exp_recurring BEFORE UPDATE ON public.exp_recurring_rules FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_and_revision();


-- --------------------------------------------------------------------
-- 7. STORAGE POLICIES (BUCKET: ledgerpulse_storage)
-- --------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public)
VALUES ('ledgerpulse_storage', 'ledgerpulse_storage', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "storage_tenant_select" ON storage.objects;
CREATE POLICY "storage_tenant_select" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'ledgerpulse_storage'
    AND (
        (storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = auth.uid()::text
        OR
        (storage.foldername(name))[1] = 'profiles' AND public.has_profile_role((storage.foldername(name))[2], ARRAY['owner','admin','accountant','manager','data_entry','viewer'])
    )
);

DROP POLICY IF EXISTS "storage_tenant_insert" ON storage.objects;
CREATE POLICY "storage_tenant_insert" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'ledgerpulse_storage'
    AND (
        (storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = auth.uid()::text
        OR
        (storage.foldername(name))[1] = 'profiles' AND public.has_profile_role((storage.foldername(name))[2], ARRAY['owner','admin','accountant','manager','data_entry'])
    )
);

DROP POLICY IF EXISTS "storage_tenant_delete" ON storage.objects;
CREATE POLICY "storage_tenant_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'ledgerpulse_storage'
    AND (
        (storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = auth.uid()::text
        OR
        (storage.foldername(name))[1] = 'profiles' AND public.has_profile_role((storage.foldername(name))[2], ARRAY['owner','admin'])
    )
);

