-- ==============================================================================
-- MIGRATION 0016: VERIFICATION SCRIPT
-- ==============================================================================
-- Purpose: Thoroughly verifies function definitions, security definer status,
-- search_path encapsulation, routine privileges, trigger attachment, and executes
-- a zero-pollution transactional test suite covering signup trigger execution,
-- idempotency, multi-workspace creation, and NULL-owner protection.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Verify existence of all functions with SECURITY DEFINER and safe search_path
-- ------------------------------------------------------------------------------
SELECT 
    routine_name, 
    security_type,
    routine_definition ILIKE '%search_path = public%' AS has_safe_search_path
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('internal_provision_workspace', 'create_workspace_profile', 'handle_new_user_registration');

-- ------------------------------------------------------------------------------
-- 2. Verify EXECUTE permissions:
-- - internal_provision_workspace: NO execution for public, anon, authenticated (postgres/service_role only)
-- - create_workspace_profile: authenticated and service_role only
-- - handle_new_user_registration: NO execution for public, anon, authenticated (postgres/service_role only)
-- ------------------------------------------------------------------------------
SELECT 
    routine_name,
    grantee,
    privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('internal_provision_workspace', 'create_workspace_profile', 'handle_new_user_registration')
ORDER BY routine_name, grantee;

-- ------------------------------------------------------------------------------
-- 3. Verify trigger existence on auth.users
-- ------------------------------------------------------------------------------
SELECT 
    tgname, 
    relname, 
    proname, 
    tgenabled
FROM pg_trigger
JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid
JOIN pg_proc ON pg_trigger.tgfoid = pg_proc.oid
JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
WHERE pg_namespace.nspname = 'auth'
  AND pg_class.relname = 'users'
  AND tgname = 'trg_on_auth_user_created';

-- ------------------------------------------------------------------------------
-- 4. Functional Test Suite in Rollback Transaction
-- Uses unique sentinel SQLSTATE 'P9999' with exact error message verification.
-- Any genuine constraint failure, syntax error, or assertion failure is re-raised.
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    v_test_uid UUID := gen_random_uuid();
    v_test_profile_id TEXT;
    v_comp_count INT;
    v_mem_count INT;
    v_prof_count INT;
    v_acc_count INT;
    v_active_co TEXT;
    v_second_res JSONB;
    v_second_profile_id TEXT;
    v_comp_total INT;
    v_mem_total INT;
    v_null_co_id TEXT := 'prf_test_null_owner_' || replace(gen_random_uuid()::text, '-', '');
    v_null_caught BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE '--- TEST A: SIMULATE NEW REGISTRATION TRIGGER ---';
    -- Insert test auth user into auth.users (simulating signup)
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
        v_test_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'audit_verify_test@example.com', 'dummy_hash', NOW(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Audit Test User"}'::jsonb,
        NOW(), NOW()
    );

    -- Verify 1 company created with owner_id = v_test_uid
    SELECT count(*), max(id) INTO v_comp_count, v_test_profile_id
    FROM public.companies WHERE owner_id = v_test_uid;
    IF v_comp_count <> 1 THEN
        RAISE EXCEPTION 'TEST A FAILED: Expected exactly 1 company for user, found %', v_comp_count;
    END IF;

    -- Verify 1 membership created with role = 'owner'
    SELECT count(*) INTO v_mem_count
    FROM public.shared_memberships WHERE account_id = v_test_uid AND profile_id = v_test_profile_id AND role = 'owner';
    IF v_mem_count <> 1 THEN
        RAISE EXCEPTION 'TEST A FAILED: Expected exactly 1 owner membership, found %', v_mem_count;
    END IF;

    -- Verify 1 user profile created with correct name and active_company_id set
    SELECT count(*), max(active_company_id) INTO v_prof_count, v_active_co
    FROM public.user_profiles WHERE id = v_test_uid::text AND name = 'Audit Test User';
    IF v_prof_count <> 1 THEN
        RAISE EXCEPTION 'TEST A FAILED: Expected user_profiles row with name "Audit Test User", found %', v_prof_count;
    END IF;
    IF v_active_co IS NULL OR v_active_co <> v_test_profile_id THEN
        RAISE EXCEPTION 'TEST A FAILED: user_profiles.active_company_id expected "%", found "%"', v_test_profile_id, v_active_co;
    END IF;

    -- Verify 12 default ledger accounts created
    SELECT count(*) INTO v_acc_count
    FROM public.accounts WHERE company_id = v_test_profile_id;
    IF v_acc_count <> 12 THEN
        RAISE EXCEPTION 'TEST A FAILED: Expected 12 accounts, found %', v_acc_count;
    END IF;
    RAISE NOTICE 'TEST A PASSED: Registration triggered 1 company, 1 membership, 1 profile, and 12 ledger accounts.';


    RAISE NOTICE '--- TEST B: IDEMPOTENCY OF DEFAULT PROVISIONING ---';
    -- Calling internal_provision_workspace again with p_is_default = TRUE must return existing default
    PERFORM public.internal_provision_workspace(
        p_user_id       => v_test_uid,
        p_name          => 'Repeated Default Attempt',
        p_profile_type  => 'ledger',
        p_is_default    => TRUE
    );

    SELECT count(*) INTO v_comp_count FROM public.companies WHERE owner_id = v_test_uid;
    IF v_comp_count <> 1 THEN
        RAISE EXCEPTION 'TEST B FAILED: Duplicate company created on idempotent retry! Found % companies', v_comp_count;
    END IF;
    RAISE NOTICE 'TEST B PASSED: Idempotent repeat prevented duplicate default workspace creation.';


    RAISE NOTICE '--- TEST C: ADDITIONAL WORKSPACE VIA MULTI-TENANT ENGINE ---';
    -- Authenticated user creates a second workspace
    v_second_res := public.internal_provision_workspace(
        p_user_id       => v_test_uid,
        p_name          => 'Audit Second Workspace',
        p_profile_type  => 'ledger',
        p_is_default    => FALSE
    );
    v_second_profile_id := v_second_res->>'profile_id';

    SELECT count(*) INTO v_comp_total FROM public.companies WHERE owner_id = v_test_uid;
    SELECT count(*) INTO v_mem_total FROM public.shared_memberships WHERE account_id = v_test_uid;

    IF v_comp_total <> 2 OR v_mem_total <> 2 THEN
        RAISE EXCEPTION 'TEST C FAILED: Expected 2 companies and 2 memberships, found % companies and % memberships',
            v_comp_total, v_mem_total;
    END IF;
    RAISE NOTICE 'TEST C PASSED: Multi-workspace creation succeeded cleanly.';


    RAISE NOTICE '--- TEST D: NULL-OWNER PROTECTION GUARD ---';
    -- Insert a synthetic unowned company (simulating legacy corrupt row with NULL owner)
    INSERT INTO public.companies (
        id, name, mode, owner_id, currency_code, is_cloud_sync_enabled, is_active, is_deleted, revision, created_at, updated_at
    ) VALUES (
        v_null_co_id, 'Unowned Legacy Workspace', 'ledger', NULL, 'INR', true, true, false, 0, NOW(), NOW()
    );

    -- Attempt to claim/adopt this unowned company must fail with a strict security violation
    BEGIN
        PERFORM public.internal_provision_workspace(
            p_user_id   => v_test_uid,
            p_name      => 'Adoption Attempt',
            p_custom_id => v_null_co_id
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%Security violation: Company "%" exists with unassigned/null ownership%' THEN
                v_null_caught := TRUE;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_null_caught THEN
        RAISE EXCEPTION 'TEST D FAILED: Adoption of company with NULL owner should have raised a security exception!';
    END IF;
    RAISE NOTICE 'TEST D PASSED: Null-owner adoption strictly rejected by security guard.';


    -- --------------------------------------------------------------------------
    -- ROLLBACK SIGNAL:
    -- Raise unique sentinel SQLSTATE 'P9999' with exact text 'ROLLBACK_VERIFICATION_COMPLETE'.
    -- Any other exception will NOT be caught as success.
    -- --------------------------------------------------------------------------
    RAISE EXCEPTION 'ROLLBACK_VERIFICATION_COMPLETE' USING ERRCODE = 'P9999';

EXCEPTION
    WHEN OTHERS THEN
        IF SQLSTATE = 'P9999' AND SQLERRM = 'ROLLBACK_VERIFICATION_COMPLETE' THEN
            RAISE NOTICE 'SUCCESS: Verification suite executed all tests successfully and rolled back test records.';
        ELSE
            -- Re-raise unexpected exceptions so verification reports failure on real bugs/constraint violations
            RAISE;
        END IF;
END $$;
