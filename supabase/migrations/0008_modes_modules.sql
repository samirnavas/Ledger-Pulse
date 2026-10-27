-- Migration 0008: Modes, Modules, Accounts, Vouchers, Journals, Budgets, and Recurring Rules
-- Aligns Supabase cloud schema with Drift local schemaVersion 8

-- 1. Alter companies table
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS mode TEXT NOT NULL DEFAULT 'ledger';
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS enabled_modules JSONB;
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS owner_id UUID DEFAULT auth.uid();

-- Ensure existing company rows default to ledger mode with all modules enabled (null)
UPDATE public.companies SET mode = 'ledger' WHERE mode IS NULL;

-- 2. Create Accounts table
CREATE TABLE IF NOT EXISTS public.accounts (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    parent_account_id TEXT,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    description TEXT,
    current_balance_in_cents BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    owner_id UUID DEFAULT auth.uid()
);

-- 3. Create Vouchers table
CREATE TABLE IF NOT EXISTS public.vouchers (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    voucher_number TEXT NOT NULL,
    type TEXT NOT NULL,
    date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    due_date TIMESTAMPTZ,
    party_id TEXT,
    party_name TEXT,
    status TEXT NOT NULL DEFAULT 'posted',
    payment_mode TEXT NOT NULL DEFAULT 'cash',
    subtotal_in_cents BIGINT NOT NULL DEFAULT 0,
    tax_in_cents BIGINT NOT NULL DEFAULT 0,
    discount_in_cents BIGINT NOT NULL DEFAULT 0,
    total_amount_in_cents BIGINT NOT NULL DEFAULT 0,
    narration TEXT,
    reference_number TEXT,
    source_voucher_id TEXT,
    receipt_photo_url TEXT,
    items_json JSONB,
    category_account_id TEXT,
    wallet_account_id TEXT,
    to_wallet_account_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    owner_id UUID DEFAULT auth.uid()
);

-- 4. Create Journals table
CREATE TABLE IF NOT EXISTS public.journals (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    journal_number TEXT NOT NULL,
    voucher_id TEXT,
    date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    narration TEXT,
    total_amount_in_cents BIGINT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'posted',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    owner_id UUID DEFAULT auth.uid()
);

-- 5. Create JournalLines table
CREATE TABLE IF NOT EXISTS public.journal_lines (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    journal_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    party_id TEXT,
    debit_in_cents BIGINT NOT NULL DEFAULT 0,
    credit_in_cents BIGINT NOT NULL DEFAULT 0,
    narration TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    owner_id UUID DEFAULT auth.uid()
);

-- 6. Create Budgets table
CREATE TABLE IF NOT EXISTS public.budgets (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    category_account_id TEXT NOT NULL,
    period_type TEXT NOT NULL DEFAULT 'monthly',
    amount_in_cents BIGINT NOT NULL DEFAULT 0,
    start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rollover_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    owner_id UUID DEFAULT auth.uid()
);

-- 7. Create RecurringRules table
CREATE TABLE IF NOT EXISTS public.recurring_rules (
    id TEXT PRIMARY KEY,
    company_id TEXT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    template_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    interval_type TEXT NOT NULL DEFAULT 'monthly',
    interval_count INTEGER NOT NULL DEFAULT 1,
    next_run_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_date TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    owner_id UUID DEFAULT auth.uid()
);

-- 8. Add (company_id, updated_at) indexes on all synced tables
CREATE INDEX IF NOT EXISTS idx_companies_updated_at ON public.companies(updated_at);
CREATE INDEX IF NOT EXISTS idx_parties_company_updated ON public.parties(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_company_updated ON public.ledger_entries(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_accounts_company_updated ON public.accounts(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_vouchers_company_updated ON public.vouchers(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_journals_company_updated ON public.journals(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_journal_lines_company_updated ON public.journal_lines(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_budgets_company_updated ON public.budgets(company_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_recurring_rules_company_updated ON public.recurring_rules(company_id, updated_at);

-- Secondary query indexes
CREATE INDEX IF NOT EXISTS idx_budgets_category_account_id ON public.budgets(category_account_id);
CREATE INDEX IF NOT EXISTS idx_recurring_rules_next_run ON public.recurring_rules(next_run_date);
CREATE INDEX IF NOT EXISTS idx_vouchers_party_id ON public.vouchers(party_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_journal_id ON public.journal_lines(journal_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account_id ON public.journal_lines(account_id);

-- 9. Row Level Security (RLS) - Mirror existing pattern (permissive for anon & authenticated)
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_rules ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'accounts' AND policyname = 'Allow public read-write on accounts') THEN
        CREATE POLICY "Allow public read-write on accounts" ON public.accounts FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'vouchers' AND policyname = 'Allow public read-write on vouchers') THEN
        CREATE POLICY "Allow public read-write on vouchers" ON public.vouchers FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'journals' AND policyname = 'Allow public read-write on journals') THEN
        CREATE POLICY "Allow public read-write on journals" ON public.journals FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'journal_lines' AND policyname = 'Allow public read-write on journal_lines') THEN
        CREATE POLICY "Allow public read-write on journal_lines" ON public.journal_lines FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'budgets' AND policyname = 'Allow public read-write on budgets') THEN
        CREATE POLICY "Allow public read-write on budgets" ON public.budgets FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'recurring_rules' AND policyname = 'Allow public read-write on recurring_rules') THEN
        CREATE POLICY "Allow public read-write on recurring_rules" ON public.recurring_rules FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
    END IF;
END $$;

-- 10. Update sync_mutation RPC to support all new tables and columns
CREATE OR REPLACE FUNCTION public.sync_mutation(table_name text, record_id text, mutation_type text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    result JSONB;
BEGIN
    IF UPPER(mutation_type) IN ('INSERT', 'UPDATE', 'UPSERT') THEN
        IF table_name = 'parties' THEN
            INSERT INTO public.parties (
                id, company_id, name, phone_number, type, net_balance_in_cents, 
                gstin, state_code, address, dealer_type,
                last_updated, is_deleted, updated_at, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE(payload->>'name', ''),
                COALESCE((payload->>'phoneNumber'), (payload->>'phone_number'), ''),
                COALESCE(payload->>'type', 'customer'),
                COALESCE((payload->>'netBalanceInCents')::BIGINT, (payload->>'net_balance_in_cents')::BIGINT, 0),
                payload->>'gstin',
                COALESCE((payload->>'stateCode'), (payload->>'state_code')),
                payload->>'address',
                COALESCE((payload->>'dealerType'), (payload->>'dealer_type'), 'regular'),
                COALESCE((payload->>'lastUpdated')::TIMESTAMPTZ, (payload->>'last_updated')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                company_id = COALESCE(EXCLUDED.company_id, public.parties.company_id),
                name = CASE WHEN EXCLUDED.name IS NOT NULL AND EXCLUDED.name <> '' THEN EXCLUDED.name ELSE public.parties.name END,
                phone_number = CASE WHEN EXCLUDED.phone_number IS NOT NULL AND EXCLUDED.phone_number <> '' THEN EXCLUDED.phone_number ELSE public.parties.phone_number END,
                type = COALESCE(EXCLUDED.type, public.parties.type),
                net_balance_in_cents = COALESCE(EXCLUDED.net_balance_in_cents, public.parties.net_balance_in_cents),
                gstin = COALESCE(EXCLUDED.gstin, public.parties.gstin),
                state_code = COALESCE(EXCLUDED.state_code, public.parties.state_code),
                address = COALESCE(EXCLUDED.address, public.parties.address),
                dealer_type = COALESCE(EXCLUDED.dealer_type, public.parties.dealer_type),
                last_updated = COALESCE(EXCLUDED.last_updated, public.parties.last_updated),
                is_deleted = COALESCE(EXCLUDED.is_deleted, public.parties.is_deleted),
                updated_at = EXCLUDED.updated_at,
                sync_status = 'synced';

        ELSIF table_name = 'ledger_entries' THEN
            INSERT INTO public.ledger_entries (
                id, company_id, party_id, amount_in_cents, type, date, note, receipt_photo_url, is_voided, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE((payload->>'partyId'), (payload->>'party_id'), ''),
                COALESCE((payload->>'amountInCents')::BIGINT, (payload->>'amount_in_cents')::BIGINT, 0),
                COALESCE(payload->>'type', 'gave'),
                COALESCE((payload->>'date')::TIMESTAMPTZ, now()),
                payload->>'note',
                COALESCE(payload->>'receiptPhotoUrl', payload->>'receipt_photo_url'),
                COALESCE((payload->>'isVoided')::BOOLEAN, (payload->>'is_voided')::BOOLEAN, false),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                party_id = EXCLUDED.party_id,
                amount_in_cents = EXCLUDED.amount_in_cents,
                type = EXCLUDED.type,
                date = EXCLUDED.date,
                note = EXCLUDED.note,
                receipt_photo_url = EXCLUDED.receipt_photo_url,
                is_voided = EXCLUDED.is_voided,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';

        ELSIF table_name = 'companies' THEN
            INSERT INTO public.companies (
                id, name, legal_name, gstin, state_code, dealer_type, currency_code, address, email, phone_number,
                logo_url, signature_url, signatory_name, bank_name, bank_account_number, bank_ifsc, upi_id,
                is_cloud_sync_enabled, is_dropbox_sync_enabled, is_active, mode, enabled_modules,
                is_deleted, created_at, updated_at, sync_status
            ) VALUES (
                record_id,
                COALESCE(payload->>'name', 'Ledger Pulse Enterprise'),
                COALESCE((payload->>'legalName'), (payload->>'legal_name'), payload->>'name', 'Ledger Pulse Enterprise'),
                payload->>'gstin',
                COALESCE((payload->>'stateCode'), (payload->>'state_code')),
                COALESCE((payload->>'dealerType'), (payload->>'dealer_type'), 'regular'),
                COALESCE((payload->>'currencyCode'), (payload->>'currency_code'), 'INR'),
                payload->>'address',
                payload->>'email',
                COALESCE((payload->>'phoneNumber'), (payload->>'phone_number')),
                COALESCE((payload->>'logoUrl'), (payload->>'logo_url')),
                COALESCE((payload->>'signatureUrl'), (payload->>'signature_url')),
                COALESCE((payload->>'signatoryName'), (payload->>'signatory_name')),
                COALESCE((payload->>'bankName'), (payload->>'bank_name')),
                COALESCE((payload->>'bankAccountNumber'), (payload->>'bank_account_number')),
                COALESCE((payload->>'bankIfsc'), (payload->>'bank_ifsc')),
                COALESCE((payload->>'upiId'), (payload->>'upi_id')),
                COALESCE((payload->>'isCloudSyncEnabled')::BOOLEAN, (payload->>'is_cloud_sync_enabled')::BOOLEAN, true),
                COALESCE((payload->>'isDropboxSyncEnabled')::BOOLEAN, (payload->>'is_dropbox_sync_enabled')::BOOLEAN, false),
                COALESCE((payload->>'isActive')::BOOLEAN, (payload->>'is_active')::BOOLEAN, true),
                COALESCE(payload->>'mode', 'ledger'),
                CASE 
                    WHEN payload ? 'enabled_modules' AND payload->'enabled_modules' IS NOT NULL AND jsonb_typeof(payload->'enabled_modules') = 'array' 
                        THEN payload->'enabled_modules'
                    WHEN payload ? 'enabledModules' AND payload->'enabledModules' IS NOT NULL AND jsonb_typeof(payload->'enabledModules') = 'array' 
                        THEN payload->'enabledModules'
                    WHEN payload ? 'enabledModulesJson' AND payload->>'enabledModulesJson' IS NOT NULL AND payload->>'enabledModulesJson' <> ''
                        THEN (payload->>'enabledModulesJson')::jsonb
                    ELSE NULL
                END,
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                name = CASE WHEN EXCLUDED.name IS NOT NULL AND EXCLUDED.name <> '' THEN EXCLUDED.name ELSE public.companies.name END,
                legal_name = CASE WHEN EXCLUDED.legal_name IS NOT NULL AND EXCLUDED.legal_name <> '' THEN EXCLUDED.legal_name ELSE public.companies.legal_name END,
                gstin = COALESCE(EXCLUDED.gstin, public.companies.gstin),
                state_code = COALESCE(EXCLUDED.state_code, public.companies.state_code),
                dealer_type = COALESCE(EXCLUDED.dealer_type, public.companies.dealer_type),
                currency_code = COALESCE(EXCLUDED.currency_code, public.companies.currency_code),
                address = COALESCE(EXCLUDED.address, public.companies.address),
                email = COALESCE(EXCLUDED.email, public.companies.email),
                phone_number = COALESCE(EXCLUDED.phone_number, public.companies.phone_number),
                logo_url = COALESCE(EXCLUDED.logo_url, public.companies.logo_url),
                signature_url = COALESCE(EXCLUDED.signature_url, public.companies.signature_url),
                signatory_name = COALESCE(EXCLUDED.signatory_name, public.companies.signatory_name),
                bank_name = COALESCE(EXCLUDED.bank_name, public.companies.bank_name),
                bank_account_number = COALESCE(EXCLUDED.bank_account_number, public.companies.bank_account_number),
                bank_ifsc = COALESCE(EXCLUDED.bank_ifsc, public.companies.bank_ifsc),
                upi_id = COALESCE(EXCLUDED.upi_id, public.companies.upi_id),
                is_cloud_sync_enabled = COALESCE(EXCLUDED.is_cloud_sync_enabled, public.companies.is_cloud_sync_enabled),
                is_dropbox_sync_enabled = COALESCE(EXCLUDED.is_dropbox_sync_enabled, public.companies.is_dropbox_sync_enabled),
                is_active = COALESCE(EXCLUDED.is_active, public.companies.is_active),
                mode = COALESCE(EXCLUDED.mode, public.companies.mode),
                enabled_modules = EXCLUDED.enabled_modules,
                is_deleted = COALESCE(EXCLUDED.is_deleted, public.companies.is_deleted),
                updated_at = EXCLUDED.updated_at,
                sync_status = 'synced';

        ELSIF table_name IN ('user_profiles', 'profiles') THEN
            INSERT INTO public.user_profiles (
                id, name, phone_number, email, business_name, address, gstin, business_type,
                bank_name, bank_account_number, bank_ifsc, upi_id, active_company_id, role,
                companies_json, is_deleted, created_at, updated_at, sync_status
            ) VALUES (
                record_id,
                COALESCE(payload->>'name', 'User'),
                COALESCE((payload->>'phoneNumber'), (payload->>'phone_number'), ''),
                COALESCE(payload->>'email', ''),
                COALESCE((payload->>'businessName'), (payload->>'business_name')),
                payload->>'address',
                payload->>'gstin',
                COALESCE((payload->>'businessType'), (payload->>'business_type')),
                COALESCE((payload->>'bankName'), (payload->>'bank_name')),
                COALESCE((payload->>'bankAccountNumber'), (payload->>'bank_account_number')),
                COALESCE((payload->>'bankIfsc'), (payload->>'bank_ifsc')),
                COALESCE((payload->>'upiId'), (payload->>'upi_id')),
                COALESCE((payload->>'activeCompanyId'), (payload->>'active_company_id'), 'cmp_default'),
                COALESCE(payload->>'role', 'admin'),
                COALESCE(payload->'companies', payload->'companies_json'),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                name = CASE WHEN EXCLUDED.name IS NOT NULL AND EXCLUDED.name <> '' THEN EXCLUDED.name ELSE public.user_profiles.name END,
                phone_number = CASE WHEN EXCLUDED.phone_number IS NOT NULL AND EXCLUDED.phone_number <> '' THEN EXCLUDED.phone_number ELSE public.user_profiles.phone_number END,
                email = CASE WHEN EXCLUDED.email IS NOT NULL AND EXCLUDED.email <> '' THEN EXCLUDED.email ELSE public.user_profiles.email END,
                business_name = COALESCE(EXCLUDED.business_name, public.user_profiles.business_name),
                address = COALESCE(EXCLUDED.address, public.user_profiles.address),
                gstin = COALESCE(EXCLUDED.gstin, public.user_profiles.gstin),
                business_type = COALESCE(EXCLUDED.business_type, public.user_profiles.business_type),
                bank_name = COALESCE(EXCLUDED.bank_name, public.user_profiles.bank_name),
                bank_account_number = COALESCE(EXCLUDED.bank_account_number, public.user_profiles.bank_account_number),
                bank_ifsc = COALESCE(EXCLUDED.bank_ifsc, public.user_profiles.bank_ifsc),
                upi_id = COALESCE(EXCLUDED.upi_id, public.user_profiles.upi_id),
                active_company_id = COALESCE(EXCLUDED.active_company_id, public.user_profiles.active_company_id),
                role = COALESCE(EXCLUDED.role, public.user_profiles.role),
                companies_json = COALESCE(EXCLUDED.companies_json, public.user_profiles.companies_json),
                is_deleted = COALESCE(EXCLUDED.is_deleted, public.user_profiles.is_deleted),
                updated_at = EXCLUDED.updated_at,
                sync_status = 'synced';

        ELSIF table_name = 'accounts' THEN
            INSERT INTO public.accounts (
                id, company_id, code, name, type, parent_account_id, is_system, is_active,
                description, current_balance_in_cents, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE(payload->>'code', ''),
                COALESCE(payload->>'name', ''),
                COALESCE(payload->>'type', 'asset'),
                COALESCE((payload->>'parentAccountId'), (payload->>'parent_account_id')),
                COALESCE((payload->>'isSystem')::BOOLEAN, (payload->>'is_system')::BOOLEAN, false),
                COALESCE((payload->>'isActive')::BOOLEAN, (payload->>'is_active')::BOOLEAN, true),
                payload->>'description',
                COALESCE((payload->>'currentBalanceInCents')::BIGINT, (payload->>'current_balance_in_cents')::BIGINT, 0),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                code = EXCLUDED.code,
                name = EXCLUDED.name,
                type = EXCLUDED.type,
                parent_account_id = EXCLUDED.parent_account_id,
                is_system = EXCLUDED.is_system,
                is_active = EXCLUDED.is_active,
                description = EXCLUDED.description,
                current_balance_in_cents = EXCLUDED.current_balance_in_cents,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';

        ELSIF table_name = 'vouchers' THEN
            INSERT INTO public.vouchers (
                id, company_id, voucher_number, type, date, due_date, party_id, party_name,
                status, payment_mode, subtotal_in_cents, tax_in_cents, discount_in_cents,
                total_amount_in_cents, narration, reference_number, source_voucher_id,
                receipt_photo_url, items_json, category_account_id, wallet_account_id,
                to_wallet_account_id, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE((payload->>'voucherNumber'), (payload->>'voucher_number'), 'VCH-001'),
                COALESCE(payload->>'type', 'sales'),
                COALESCE((payload->>'date')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'dueDate')::TIMESTAMPTZ, (payload->>'due_date')::TIMESTAMPTZ),
                COALESCE((payload->>'partyId'), (payload->>'party_id')),
                COALESCE((payload->>'partyName'), (payload->>'party_name')),
                COALESCE(payload->>'status', 'posted'),
                COALESCE((payload->>'paymentMode'), (payload->>'payment_mode'), 'cash'),
                COALESCE((payload->>'subtotalInCents')::BIGINT, (payload->>'subtotal_in_cents')::BIGINT, 0),
                COALESCE((payload->>'taxInCents')::BIGINT, (payload->>'tax_in_cents')::BIGINT, 0),
                COALESCE((payload->>'discountInCents')::BIGINT, (payload->>'discount_in_cents')::BIGINT, 0),
                COALESCE((payload->>'totalAmountInCents')::BIGINT, (payload->>'total_amount_in_cents')::BIGINT, 0),
                payload->>'narration',
                COALESCE((payload->>'referenceNumber'), (payload->>'reference_number')),
                COALESCE((payload->>'sourceVoucherId'), (payload->>'source_voucher_id')),
                COALESCE((payload->>'receiptPhotoUrl'), (payload->>'receipt_photo_url')),
                CASE 
                    WHEN payload ? 'items_json' AND payload->'items_json' IS NOT NULL AND jsonb_typeof(payload->'items_json') <> 'null' THEN payload->'items_json'
                    WHEN payload ? 'itemsJson' AND payload->>'itemsJson' IS NOT NULL AND payload->>'itemsJson' <> '' THEN (payload->>'itemsJson')::jsonb
                    ELSE NULL
                END,
                COALESCE((payload->>'categoryAccountId'), (payload->>'category_account_id')),
                COALESCE((payload->>'walletAccountId'), (payload->>'wallet_account_id')),
                COALESCE((payload->>'toWalletAccountId'), (payload->>'to_wallet_account_id')),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                voucher_number = EXCLUDED.voucher_number,
                type = EXCLUDED.type,
                date = EXCLUDED.date,
                due_date = EXCLUDED.due_date,
                party_id = EXCLUDED.party_id,
                party_name = EXCLUDED.party_name,
                status = EXCLUDED.status,
                payment_mode = EXCLUDED.payment_mode,
                subtotal_in_cents = EXCLUDED.subtotal_in_cents,
                tax_in_cents = EXCLUDED.tax_in_cents,
                discount_in_cents = EXCLUDED.discount_in_cents,
                total_amount_in_cents = EXCLUDED.total_amount_in_cents,
                narration = EXCLUDED.narration,
                reference_number = EXCLUDED.reference_number,
                source_voucher_id = EXCLUDED.source_voucher_id,
                receipt_photo_url = EXCLUDED.receipt_photo_url,
                items_json = EXCLUDED.items_json,
                category_account_id = EXCLUDED.category_account_id,
                wallet_account_id = EXCLUDED.wallet_account_id,
                to_wallet_account_id = EXCLUDED.to_wallet_account_id,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';

        ELSIF table_name = 'journals' THEN
            INSERT INTO public.journals (
                id, company_id, journal_number, voucher_id, date, narration,
                total_amount_in_cents, status, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE((payload->>'journalNumber'), (payload->>'journal_number'), 'JRN-001'),
                COALESCE((payload->>'voucherId'), (payload->>'voucher_id')),
                COALESCE((payload->>'date')::TIMESTAMPTZ, now()),
                payload->>'narration',
                COALESCE((payload->>'totalAmountInCents')::BIGINT, (payload->>'total_amount_in_cents')::BIGINT, 0),
                COALESCE(payload->>'status', 'posted'),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                journal_number = EXCLUDED.journal_number,
                voucher_id = EXCLUDED.voucher_id,
                date = EXCLUDED.date,
                narration = EXCLUDED.narration,
                total_amount_in_cents = EXCLUDED.total_amount_in_cents,
                status = EXCLUDED.status,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';

        ELSIF table_name = 'journal_lines' THEN
            INSERT INTO public.journal_lines (
                id, company_id, journal_id, account_id, party_id,
                debit_in_cents, credit_in_cents, narration, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE((payload->>'journalId'), (payload->>'journal_id'), ''),
                COALESCE((payload->>'accountId'), (payload->>'account_id'), ''),
                COALESCE((payload->>'partyId'), (payload->>'party_id')),
                COALESCE((payload->>'debitInCents')::BIGINT, (payload->>'debit_in_cents')::BIGINT, 0),
                COALESCE((payload->>'creditInCents')::BIGINT, (payload->>'credit_in_cents')::BIGINT, 0),
                payload->>'narration',
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                journal_id = EXCLUDED.journal_id,
                account_id = EXCLUDED.account_id,
                party_id = EXCLUDED.party_id,
                debit_in_cents = EXCLUDED.debit_in_cents,
                credit_in_cents = EXCLUDED.credit_in_cents,
                narration = EXCLUDED.narration,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';

        ELSIF table_name = 'budgets' THEN
            INSERT INTO public.budgets (
                id, company_id, category_account_id, period_type, amount_in_cents,
                start_date, rollover_enabled, is_active, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                COALESCE((payload->>'categoryAccountId'), (payload->>'category_account_id'), ''),
                COALESCE((payload->>'periodType'), (payload->>'period_type'), 'monthly'),
                COALESCE((payload->>'amountInCents')::BIGINT, (payload->>'amount_in_cents')::BIGINT, 0),
                COALESCE((payload->>'startDate')::TIMESTAMPTZ, (payload->>'start_date')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'rolloverEnabled')::BOOLEAN, (payload->>'rollover_enabled')::BOOLEAN, false),
                COALESCE((payload->>'isActive')::BOOLEAN, (payload->>'is_active')::BOOLEAN, true),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                category_account_id = EXCLUDED.category_account_id,
                period_type = EXCLUDED.period_type,
                amount_in_cents = EXCLUDED.amount_in_cents,
                start_date = EXCLUDED.start_date,
                rollover_enabled = EXCLUDED.rollover_enabled,
                is_active = EXCLUDED.is_active,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';

        ELSIF table_name = 'recurring_rules' THEN
            INSERT INTO public.recurring_rules (
                id, company_id, template_json, interval_type, interval_count,
                next_run_date, end_date, is_active, created_at, updated_at, is_deleted, sync_status
            ) VALUES (
                record_id,
                COALESCE((payload->>'companyId'), (payload->>'company_id'), 'cmp_default'),
                CASE 
                    WHEN payload ? 'template_json' AND payload->'template_json' IS NOT NULL AND jsonb_typeof(payload->'template_json') <> 'null' THEN payload->'template_json'
                    WHEN payload ? 'templateJson' AND payload->>'templateJson' IS NOT NULL AND payload->>'templateJson' <> '' THEN (payload->>'templateJson')::jsonb
                    ELSE '{}'::jsonb
                END,
                COALESCE((payload->>'intervalType'), (payload->>'interval_type'), 'monthly'),
                COALESCE((payload->>'intervalCount')::INTEGER, (payload->>'interval_count')::INTEGER, 1),
                COALESCE((payload->>'nextRunDate')::TIMESTAMPTZ, (payload->>'next_run_date')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'endDate')::TIMESTAMPTZ, (payload->>'end_date')::TIMESTAMPTZ),
                COALESCE((payload->>'isActive')::BOOLEAN, (payload->>'is_active')::BOOLEAN, true),
                COALESCE((payload->>'createdAt')::TIMESTAMPTZ, (payload->>'created_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'updatedAt')::TIMESTAMPTZ, (payload->>'updated_at')::TIMESTAMPTZ, now()),
                COALESCE((payload->>'isDeleted')::BOOLEAN, (payload->>'is_deleted')::BOOLEAN, false),
                'synced'
            )
            ON CONFLICT (id) DO UPDATE SET
                template_json = EXCLUDED.template_json,
                interval_type = EXCLUDED.interval_type,
                interval_count = EXCLUDED.interval_count,
                next_run_date = EXCLUDED.next_run_date,
                end_date = EXCLUDED.end_date,
                is_active = EXCLUDED.is_active,
                updated_at = EXCLUDED.updated_at,
                is_deleted = EXCLUDED.is_deleted,
                sync_status = 'synced';
        END IF;

    ELSIF UPPER(mutation_type) = 'DELETE' THEN
        IF table_name = 'parties' THEN
            UPDATE public.parties SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'ledger_entries' THEN
            UPDATE public.ledger_entries SET is_deleted = true, is_voided = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'companies' THEN
            UPDATE public.companies SET is_deleted = true, is_active = false, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name IN ('user_profiles', 'profiles') THEN
            UPDATE public.user_profiles SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'accounts' THEN
            UPDATE public.accounts SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'vouchers' THEN
            UPDATE public.vouchers SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'journals' THEN
            UPDATE public.journals SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'journal_lines' THEN
            UPDATE public.journal_lines SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'budgets' THEN
            UPDATE public.budgets SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        ELSIF table_name = 'recurring_rules' THEN
            UPDATE public.recurring_rules SET is_deleted = true, updated_at = now(), sync_status = 'synced' WHERE id = record_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'record_id', record_id, 'table_name', table_name);
END;
$function$;
