-- ==============================================================================
-- SUPABASE MIGRATION 0016: AUTOMATIC USER PROVISIONING TRIGGER & SHARED RPC ARCHITECTURE
-- Target: LedgerPulse Supabase / PostgreSQL (Schema: public / auth)
-- Purpose: Atomically and idempotently provisions user_profiles, default ledger workspace,
--          owner membership, and 12 canonical chart of accounts upon registration.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- PRE-CONDITION VERIFICATION:
-- Verify no conflicting trigger named trg_on_auth_user_created already exists
-- pointing to an unknown/different function on auth.users.
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    v_existing_proc TEXT;
BEGIN
    SELECT p.proname INTO v_existing_proc
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_proc p ON t.tgfoid = p.oid
    WHERE n.nspname = 'auth'
      AND c.relname = 'users'
      AND t.tgname = 'trg_on_auth_user_created';

    IF v_existing_proc IS NOT NULL AND v_existing_proc <> 'handle_new_user_registration' THEN
        RAISE EXCEPTION 'MIGRATION 0016 ABORT: An existing trigger named "trg_on_auth_user_created" already exists on auth.users pointing to unexpected function "%". Aborting to prevent overwriting existing behavior.', v_existing_proc;
    END IF;
END $$;


-- ------------------------------------------------------------------------------
-- 1. SHARED INTERNAL WORKSPACE PROVISIONING FUNCTION (SECURITY DEFINER)
-- ------------------------------------------------------------------------------
-- Core shared engine that provisions a workspace for an explicitly specified user UUID.
-- Callable internally by the auth registration trigger and the authenticated RPC wrapper.
-- Direct execution by anon / authenticated roles is explicitly revoked.
CREATE OR REPLACE FUNCTION public.internal_provision_workspace(
    p_user_id UUID,
    p_name TEXT,
    p_profile_type TEXT DEFAULT 'ledger',
    p_currency_code TEXT DEFAULT 'INR',
    p_legal_name TEXT DEFAULT NULL,
    p_gstin TEXT DEFAULT NULL,
    p_custom_id TEXT DEFAULT NULL,
    p_is_default BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_profile_id TEXT;
    v_existing_profile_id TEXT;
    v_existing_owner UUID;
    v_existing_mode TEXT;
    v_existing_name TEXT;
    v_verified_owner UUID;
    v_profile_type TEXT;
    v_legal_name TEXT;
    v_currency TEXT;
    v_company_found BOOLEAN := FALSE;
BEGIN
    -- 1. Validate mandatory user identifier
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'Provisioning failed: Target user UUID cannot be null.';
    END IF;

    -- 2. Concurrency Control: Serialize default provisioning per user via transaction-scoped advisory lock
    -- Guarantees that concurrent requests for the same user (e.g. auth trigger + immediate client login/sync)
    -- do not race or create duplicate default workspaces.
    PERFORM pg_advisory_xact_lock(hashtext('internal_provision_workspace'::text), hashtext(p_user_id::text));

    -- 3. Validate Profile Type
    v_profile_type := LOWER(TRIM(COALESCE(p_profile_type, 'ledger')));
    IF v_profile_type NOT IN ('expense', 'ledger') THEN
        RAISE EXCEPTION 'Invalid profile_type "%". Must be "expense" or "ledger".', p_profile_type;
    END IF;

    -- 4. Idempotency Guard for Default Workspace Registration:
    -- If provisioning default workspace and user already owns a workspace, return existing without duplicating
    IF p_is_default THEN
        SELECT m.profile_id INTO v_existing_profile_id
        FROM public.shared_memberships m
        JOIN public.companies c ON c.id = m.profile_id
        WHERE m.account_id = p_user_id 
          AND m.role = 'owner' 
          AND c.is_deleted = false
        ORDER BY m.joined_at ASC
        LIMIT 1;

        IF v_existing_profile_id IS NOT NULL THEN
            SELECT name, mode INTO v_existing_name, v_profile_type
            FROM public.companies WHERE id = v_existing_profile_id;

            RETURN jsonb_build_object(
                'success', true,
                'action', 'retrieved_existing_default',
                'profile_id', v_existing_profile_id,
                'profile_type', v_profile_type,
                'name', v_existing_name
            );
        END IF;
    END IF;

    -- 5. Determine Profile Identifier
    IF p_custom_id IS NOT NULL AND TRIM(p_custom_id) <> '' THEN
        v_profile_id := TRIM(p_custom_id);
    ELSE
        v_profile_id := 'prf_' || replace(gen_random_uuid()::text, '-', '');
    END IF;

    v_legal_name := COALESCE(NULLIF(TRIM(p_legal_name), ''), TRIM(p_name));
    v_currency := UPPER(COALESCE(NULLIF(TRIM(p_currency_code), ''), 'INR'));

    -- 6. Lock and Inspect Existing Company Row (Distinguish missing vs null owner vs other owner)
    SELECT owner_id, mode, name
    INTO v_existing_owner, v_existing_mode, v_existing_name
    FROM public.companies
    WHERE id = v_profile_id
    FOR UPDATE;

    IF FOUND THEN
        v_company_found := TRUE;
        -- Explicitly check for NULL owner: Never adopt or assign a company with a NULL owner!
        IF v_existing_owner IS NULL THEN
            RAISE EXCEPTION 'Security violation: Company "%" exists with unassigned/null ownership. Automatic adoption is prohibited by architecture.', v_profile_id;
        END IF;

        -- Check ownership: caller must be the recorded owner or already hold an owner membership
        IF v_existing_owner = p_user_id OR EXISTS (
            SELECT 1 FROM public.shared_memberships
            WHERE profile_id = v_profile_id AND account_id = p_user_id AND role = 'owner'
        ) THEN
            RETURN jsonb_build_object(
                'success', true,
                'action', 'retrieved_existing',
                'profile_id', v_profile_id,
                'profile_type', v_existing_mode,
                'name', v_existing_name
            );
        ELSE
            RAISE EXCEPTION 'Security violation: Profile ID "%" already exists and is owned by another account.', v_profile_id;
        END IF;
    END IF;

    -- 7. Insert Workspace into public.companies if not already found
    IF NOT v_company_found THEN
        INSERT INTO public.companies (
            id, name, legal_name, mode, owner_id, currency_code, gstin,
            is_cloud_sync_enabled, is_active, is_deleted, revision, created_at, updated_at
        ) VALUES (
            v_profile_id, TRIM(p_name), v_legal_name, v_profile_type, p_user_id, v_currency, NULLIF(TRIM(p_gstin), ''),
            true, true, false, 0, NOW(), NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
            updated_at = NOW()
        WHERE public.companies.owner_id = p_user_id;

        -- 8. Post-Conflict Ownership Verification:
        -- Verify that the company actually belongs to p_user_id before creating any membership!
        SELECT owner_id INTO v_verified_owner
        FROM public.companies
        WHERE id = v_profile_id;

        IF v_verified_owner IS NULL OR v_verified_owner <> p_user_id THEN
            RAISE EXCEPTION 'Ownership verification failed: Company "%" was not created by user "%" or has unassigned owner.',
                v_profile_id, p_user_id;
        END IF;
    END IF;

    -- 9. Insert Owner Membership into public.shared_memberships
    -- Only executed AFTER ownership of v_profile_id is strictly verified!
    INSERT INTO public.shared_memberships (
        id, profile_id, account_id, role, joined_at, updated_at
    ) VALUES (
        gen_random_uuid(), v_profile_id, p_user_id, 'owner', NOW(), NOW()
    )
    ON CONFLICT (profile_id, account_id) DO UPDATE 
    SET role = 'owner', updated_at = NOW();

    -- 10. Seed Canonical Domain Defaults Idempotently
    IF v_profile_type = 'ledger' THEN
        -- Seed Standard 12 Indian Accounting Chart of Accounts
        INSERT INTO public.accounts (
            id, company_id, code, name, type, kind, is_system, is_active,
            current_balance_in_cents, is_deleted, owner_id, revision, created_at, updated_at, sync_status
        ) VALUES
            (v_profile_id || '_acc_cash', v_profile_id, '1001', 'Cash in Hand', 'asset', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_bank', v_profile_id, '1002', 'Bank Account', 'asset', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_debtors', v_profile_id, '1003', 'Sundry Debtors', 'asset', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_cgst_in', v_profile_id, '1004', 'Input CGST', 'asset', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_sgst_in', v_profile_id, '1005', 'Input SGST', 'asset', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_igst_in', v_profile_id, '1006', 'Input IGST', 'asset', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_creditors', v_profile_id, '2001', 'Sundry Creditors', 'liability', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_cgst_out', v_profile_id, '2002', 'Output CGST', 'liability', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_sgst_out', v_profile_id, '2003', 'Output SGST', 'liability', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_igst_out', v_profile_id, '2004', 'Output IGST', 'liability', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_sales', v_profile_id, '3001', 'Sales Account', 'income', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced'),
            (v_profile_id || '_acc_purchases', v_profile_id, '4001', 'Purchase Account', 'expense', 'system', true, true, 0, false, p_user_id, 0, NOW(), NOW(), 'synced')
        ON CONFLICT (id) DO NOTHING;

    ELSIF v_profile_type = 'expense' THEN
        -- Seed Default Expense Wallets
        INSERT INTO public.exp_wallets (
            id, profile_id, name, wallet_type, currency_code, starting_balance_in_cents, current_balance_in_cents,
            color_hex, icon_name, is_archived, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_wal_cash', v_profile_id, 'Cash in Hand', 'cash', v_currency, 0, 0, '#006C4C', 'payments', false, false, 0, NOW(), NOW()),
            (v_profile_id || '_wal_bank', v_profile_id, 'Bank Account', 'bank', v_currency, 0, 0, '#005AC1', 'account_balance', false, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;

        -- Seed Default Expense Categories
        INSERT INTO public.exp_categories (
            id, profile_id, name, category_type, is_system, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_cat_food', v_profile_id, 'Food & Dining', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_groceries', v_profile_id, 'Groceries', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_utilities', v_profile_id, 'Utilities & Bills', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_transport', v_profile_id, 'Transportation', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_rent', v_profile_id, 'Rent & Housing', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_shopping', v_profile_id, 'Shopping', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_salary', v_profile_id, 'Salary', 'income', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_freelance', v_profile_id, 'Freelance / Business', 'income', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_investments', v_profile_id, 'Investments', 'income', true, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'created_new',
        'profile_id', v_profile_id,
        'profile_type', v_profile_type,
        'name', TRIM(p_name)
    );
END;
$function$;

-- Strict Access Control: Revoke execute from public/anon/authenticated; permit only trusted system roles
REVOKE EXECUTE ON FUNCTION public.internal_provision_workspace(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.internal_provision_workspace(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO postgres, service_role;


-- ------------------------------------------------------------------------------
-- 2. REFACTORED AUTHENTICATED WORKSPACE RPC (PUBLIC API COMPATIBLE)
-- ------------------------------------------------------------------------------
-- Preserves existing create_workspace_profile() signature and behavior.
-- Forwards the cryptographically verified auth.uid() to internal_provision_workspace().
CREATE OR REPLACE FUNCTION public.create_workspace_profile(
    p_name TEXT,
    p_profile_type TEXT,
    p_currency_code TEXT DEFAULT 'INR',
    p_legal_name TEXT DEFAULT NULL,
    p_gstin TEXT DEFAULT NULL,
    p_custom_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_user_id UUID;
BEGIN
    -- Verify caller authentication strictly server-side
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required: auth.uid() is null.';
    END IF;

    -- Delegate to shared provisioning engine with authenticated caller's UUID
    RETURN public.internal_provision_workspace(
        p_user_id       => v_user_id,
        p_name          => p_name,
        p_profile_type  => p_profile_type,
        p_currency_code => p_currency_code,
        p_legal_name    => p_legal_name,
        p_gstin         => p_gstin,
        p_custom_id     => p_custom_id,
        p_is_default    => FALSE
    );
END;
$function$;

-- Grant execution to authenticated users and service_role; revoke from public/anon
REVOKE EXECUTE ON FUNCTION public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;


-- ------------------------------------------------------------------------------
-- 3. AUTOMATIC AUTH REGISTRATION HANDLER & TRIGGER
-- ------------------------------------------------------------------------------
-- Triggered automatically AFTER INSERT ON auth.users.
-- Runs in the same transaction as user creation.
CREATE OR REPLACE FUNCTION public.handle_new_user_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_full_name TEXT;
    v_workspace_name TEXT;
    v_profile_res JSONB;
BEGIN
    -- 1. Extract Full Name from raw_user_meta_data candidates
    -- Apply NULLIF(TRIM(...), '') to EACH candidate before COALESCE to ensure blank strings fall through
    v_full_name := COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'user_name'), '')
    );

    -- 2. Derive Workspace Name:
    -- Priority 1: User's full name where available
    -- Priority 2: Derived from email prefix
    -- Priority 3: Fallback 'My Ledger'
    IF v_full_name IS NOT NULL THEN
        v_workspace_name := v_full_name;
    ELSIF NEW.email IS NOT NULL AND TRIM(NEW.email) <> '' AND POSITION('@' IN NEW.email) > 1 THEN
        v_workspace_name := INITCAP(REPLACE(SPLIT_PART(TRIM(NEW.email), '@', 1), '.', ' '));
        IF v_workspace_name IS NULL OR TRIM(v_workspace_name) = '' THEN
            v_workspace_name := 'My Ledger';
        END IF;
    ELSE
        v_workspace_name := 'My Ledger';
    END IF;

    -- Guarantee non-empty user display name for user_profiles
    IF v_full_name IS NULL THEN
        v_full_name := COALESCE(NULLIF(TRIM(v_workspace_name), ''), 'User');
    END IF;

    -- 3. Provision user_profiles record atomically
    INSERT INTO public.user_profiles (
        id,
        name,
        email,
        phone_number,
        business_name,
        role,
        owner_id,
        created_at,
        updated_at,
        sync_status,
        revision
    ) VALUES (
        NEW.id::text,
        v_full_name,
        COALESCE(TRIM(NEW.email), ''),
        COALESCE(TRIM(NEW.phone), ''),
        v_workspace_name,
        'admin',
        NEW.id,
        NOW(),
        NOW(),
        'synced',
        0
    ) ON CONFLICT (id) DO UPDATE SET
        name = CASE WHEN public.user_profiles.name IS NULL OR public.user_profiles.name = '' THEN EXCLUDED.name ELSE public.user_profiles.name END,
        email = CASE WHEN public.user_profiles.email IS NULL OR public.user_profiles.email = '' THEN EXCLUDED.email ELSE public.user_profiles.email END,
        phone_number = CASE WHEN public.user_profiles.phone_number IS NULL OR public.user_profiles.phone_number = '' THEN EXCLUDED.phone_number ELSE public.user_profiles.phone_number END,
        owner_id = COALESCE(public.user_profiles.owner_id, EXCLUDED.owner_id),
        updated_at = NOW();

    -- 4. Provision Default Ledger Workspace & 12 Accounts via shared internal engine
    v_profile_res := public.internal_provision_workspace(
        p_user_id       => NEW.id,
        p_name          => v_workspace_name,
        p_profile_type  => 'ledger',
        p_currency_code => 'INR',
        p_legal_name    => v_workspace_name,
        p_gstin         => NULL,
        p_custom_id     => NULL,
        p_is_default    => TRUE
    );

    -- 5. Link newly provisioned workspace as user's active_company_id
    IF v_profile_res->>'profile_id' IS NOT NULL THEN
        UPDATE public.user_profiles
        SET active_company_id = v_profile_res->>'profile_id'
        WHERE id = NEW.id::text
          AND (active_company_id IS NULL OR active_company_id = '' OR active_company_id = 'cmp_default');
    END IF;

    RETURN NEW;
END;
$function$;

-- Strict Access Control: Revoke execute from public/anon/authenticated
REVOKE EXECUTE ON FUNCTION public.handle_new_user_registration() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user_registration() TO postgres, service_role;

-- 4. Install repeatable trigger on auth.users
DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user_registration();
