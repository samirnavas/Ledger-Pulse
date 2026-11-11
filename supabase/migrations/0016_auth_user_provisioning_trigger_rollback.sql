-- ==============================================================================
-- MIGRATION 0016: ROLLBACK SCRIPT
-- ==============================================================================
--
-- PRE-MIGRATION STATE DOCUMENTATION:
-- Baseline prior to Migration 0016:
-- 1. No trigger named "trg_on_auth_user_created" existed on table "auth.users".
--    (Verified against migrations 0001 through 0015 and pg_trigger catalogue).
-- 2. Function "public.create_workspace_profile" was defined in Migration 0012
--    (supabase/migrations/0012_target_rpcs_and_sync.sql, lines 13-138) with direct
--    standalone workspace insertion logic.
-- 3. Functions "public.internal_provision_workspace" and
--    "public.handle_new_user_registration" did not exist prior to Migration 0016.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- PRE-ROLLBACK VERIFICATION:
-- Verify that trg_on_auth_user_created actually points to handle_new_user_registration
-- before dropping it, to prevent unintended drops of any third-party triggers.
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
        RAISE EXCEPTION 'ROLLBACK ABORT: Trigger "trg_on_auth_user_created" points to unexpected function "%", not "handle_new_user_registration". Aborting rollback to prevent unintended side effects.', v_existing_proc;
    END IF;
END $$;

-- 1. Drop trigger on auth.users
DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;

-- 2. Drop auth registration trigger function
DROP FUNCTION IF EXISTS public.handle_new_user_registration();

-- 3. Restore original 0012 standalone create_workspace_profile function
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
SET search_path = public
AS $function$
DECLARE
    v_user_id UUID;
    v_profile_id TEXT;
    v_existing_owner UUID;
    v_profile_type TEXT;
    v_legal_name TEXT;
    v_currency TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required: auth.uid() is null.';
    END IF;

    v_profile_type := LOWER(TRIM(p_profile_type));
    IF v_profile_type NOT IN ('expense', 'ledger') THEN
        RAISE EXCEPTION 'Invalid profile_type "%". Must be "expense" or "ledger".', p_profile_type;
    END IF;

    IF p_custom_id IS NOT NULL AND TRIM(p_custom_id) <> '' THEN
        v_profile_id := TRIM(p_custom_id);
    ELSE
        v_profile_id := 'prf_' || replace(gen_random_uuid()::text, '-', '');
    END IF;

    v_legal_name := COALESCE(NULLIF(TRIM(p_legal_name), ''), TRIM(p_name));
    v_currency := UPPER(COALESCE(NULLIF(TRIM(p_currency_code), ''), 'INR'));

    SELECT owner_id INTO v_existing_owner
    FROM public.companies
    WHERE id = v_profile_id;

    IF v_existing_owner IS NOT NULL THEN
        IF v_existing_owner = v_user_id OR EXISTS (
            SELECT 1 FROM public.shared_memberships
            WHERE profile_id = v_profile_id AND account_id = v_user_id AND role = 'owner'
        ) THEN
            RETURN jsonb_build_object(
                'success', true,
                'action', 'retrieved_existing',
                'profile_id', v_profile_id,
                'profile_type', v_profile_type,
                'name', p_name
            );
        ELSE
            RAISE EXCEPTION 'Profile ID "%" already exists and is owned by another account.', v_profile_id;
        END IF;
    END IF;

    INSERT INTO public.companies (
        id, name, legal_name, mode, owner_id, currency_code, gstin,
        is_cloud_sync_enabled, is_active, is_deleted, revision, created_at, updated_at
    ) VALUES (
        v_profile_id, TRIM(p_name), v_legal_name, v_profile_type, v_user_id, v_currency, NULLIF(TRIM(p_gstin), ''),
        true, true, false, 0, NOW(), NOW()
    );

    INSERT INTO public.shared_memberships (
        profile_id, account_id, role, joined_at, updated_at
    ) VALUES (
        v_profile_id, v_user_id, 'owner', NOW(), NOW()
    )
    ON CONFLICT (profile_id, account_id) DO UPDATE SET role = 'owner';

    IF v_profile_type = 'expense' THEN
        INSERT INTO public.exp_wallets (
            id, profile_id, name, wallet_type, currency_code, starting_balance_in_cents, current_balance_in_cents, color_hex, icon_name, is_archived, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_wal_cash', v_profile_id, 'Cash in Hand', 'cash', v_currency, 0, 0, '#006C4C', 'payments', false, false, 0, NOW(), NOW()),
            (v_profile_id || '_wal_bank', v_profile_id, 'Bank Account', 'bank', v_currency, 0, 0, '#005AC1', 'account_balance', false, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;

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
    ELSIF v_profile_type = 'ledger' THEN
        INSERT INTO public.accounts (
            id, company_id, code, name, type, kind, is_system, is_active, current_balance_in_cents, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_acc_cash', v_profile_id, '1001', 'Cash in Hand', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_bank', v_profile_id, '1002', 'Bank Account', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_debtors', v_profile_id, '1003', 'Sundry Debtors', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_cgst_in', v_profile_id, '1004', 'Input CGST', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_sgst_in', v_profile_id, '1005', 'Input SGST', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_igst_in', v_profile_id, '1006', 'Input IGST', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_creditors', v_profile_id, '2001', 'Sundry Creditors', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_cgst_out', v_profile_id, '2002', 'Output CGST', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_sgst_out', v_profile_id, '2003', 'Output SGST', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_igst_out', v_profile_id, '2004', 'Output IGST', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_sales', v_profile_id, '3001', 'Sales Account', 'income', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_purchases', v_profile_id, '4001', 'Purchase Account', 'expense', 'system', true, true, 0, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'created_new',
        'profile_id', v_profile_id,
        'profile_type', v_profile_type,
        'name', p_name
    );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- 4. Drop internal shared provisioning function
DROP FUNCTION IF EXISTS public.internal_provision_workspace(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN);
