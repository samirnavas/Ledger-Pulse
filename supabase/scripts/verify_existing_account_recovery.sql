-- ==============================================================================
-- SCRIPT: VERIFY EXISTING ACCOUNT RECOVERY (DRY-RUN & TRANSACTIONAL TEST SUITE)
-- Target: LedgerPulse Supabase / PostgreSQL (Schemas: auth, public)
-- Purpose: Evaluates database state, generates dry-run recovery statistics,
--          runs a zero-pollution transactional test of the recovery logic using
--          unique sentinel exception P9999, and checks for remaining inconsistencies.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. DRY-RUN RECOVERY AUDIT: Assess what would be created or changed
-- ------------------------------------------------------------------------------
WITH user_health AS (
    SELECT 
        u.id AS user_id,
        u.email,
        u.created_at,
        up.id IS NOT NULL AS has_user_profile,
        up.active_company_id,
        
        COUNT(DISTINCT c.id) AS owned_companies_count,
        COALESCE(MAX(c.id), NULL) AS existing_owned_co_id,
        COALESCE(MAX(c.mode), NULL) AS existing_owned_co_mode,
        
        COUNT(DISTINCT m.id) AS total_memberships_count,
        COUNT(DISTINCT m.id) FILTER (WHERE m.role = 'owner') AS owner_memberships_count,
        
        COUNT(DISTINCT a.id) AS accounts_count,
        
        EXISTS (
            SELECT 1 FROM public.companies c_act 
            WHERE c_act.id = up.active_company_id AND c_act.is_deleted = false
        ) AS is_active_company_valid,

        EXISTS (
            SELECT 1 FROM public.companies c_null
            JOIN public.shared_memberships sm_null ON sm_null.profile_id = c_null.id
            WHERE sm_null.account_id = u.id AND c_null.owner_id IS NULL
        ) AS has_null_owner_conflict

    FROM auth.users u
    LEFT JOIN public.user_profiles up ON up.id = u.id::text OR up.owner_id = u.id
    LEFT JOIN public.companies c ON c.owner_id = u.id AND c.is_deleted = false
    LEFT JOIN public.shared_memberships m ON m.account_id = u.id
    LEFT JOIN public.accounts a ON a.company_id = c.id AND a.is_deleted = false
    GROUP BY u.id, u.email, u.created_at, up.id, up.active_company_id
),
forecasted_actions AS (
    SELECT 
        h.*,
        CASE
            WHEN h.has_null_owner_conflict THEN 'REQUIRES_MANUAL_REVIEW'
            WHEN h.has_user_profile AND h.owned_companies_count >= 1 AND h.owner_memberships_count >= 1 AND h.is_active_company_valid AND h.accounts_count >= 12 THEN 'HEALTHY_PRESERVED'
            WHEN h.owned_companies_count = 0 AND h.total_memberships_count = 0 THEN 'ELIGIBLE_FOR_AUTOMATIC_RECOVERY'
            WHEN h.owned_companies_count >= 1 THEN 'ELIGIBLE_FOR_PARTIAL_REPAIR'
            WHEN h.owned_companies_count = 0 AND h.total_memberships_count > 0 THEN 'INVITED_COLLABORATOR_PRESERVED'
            ELSE 'REQUIRES_MANUAL_REVIEW'
        END AS dry_run_status,

        -- Profiles needed
        CASE WHEN NOT h.has_user_profile THEN 1 ELSE 0 END AS profile_to_create,
        
        -- Workspaces needed
        CASE WHEN h.owned_companies_count = 0 AND h.total_memberships_count = 0 THEN 1 ELSE 0 END AS workspace_to_create,
        
        -- Memberships needed
        CASE 
            WHEN h.owned_companies_count = 0 AND h.total_memberships_count = 0 THEN 1
            WHEN h.owned_companies_count >= 1 AND h.owner_memberships_count = 0 THEN 1
            ELSE 0 
        END AS membership_to_create,

        -- Accounts needed
        CASE 
            WHEN h.owned_companies_count = 0 AND h.total_memberships_count = 0 THEN 12
            WHEN h.owned_companies_count >= 1 AND h.accounts_count < 12 THEN GREATEST(12 - h.accounts_count, 0)
            ELSE 0 
        END AS accounts_to_create
    FROM user_health h
)
SELECT 
    COUNT(*) AS total_users_inspected,
    COUNT(*) FILTER (WHERE dry_run_status IN ('ELIGIBLE_FOR_AUTOMATIC_RECOVERY', 'ELIGIBLE_FOR_PARTIAL_REPAIR')) AS users_eligible_for_recovery,
    COUNT(*) FILTER (WHERE dry_run_status = 'REQUIRES_MANUAL_REVIEW') AS users_requiring_manual_review,
    COUNT(*) FILTER (WHERE dry_run_status IN ('HEALTHY_PRESERVED', 'INVITED_COLLABORATOR_PRESERVED')) AS users_already_healthy_or_collaborators,
    SUM(profile_to_create) AS user_profiles_to_create,
    SUM(workspace_to_create) AS default_workspaces_to_create,
    SUM(membership_to_create) AS memberships_to_create,
    SUM(accounts_to_create) AS default_accounts_to_create
FROM forecasted_actions;


-- ------------------------------------------------------------------------------
-- 2. TRANSACTIONAL DRY-RUN & INTEGRITY TEST
-- Simulates the exact recovery process inside a transaction and rolls back
-- using unique sentinel SQLSTATE 'P9999'. Any unexpected database error re-raises.
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    v_test_uid UUID := gen_random_uuid();
    v_test_co_id TEXT;
    v_comp_count INT;
    v_mem_count INT;
    v_prof_count INT;
    v_acc_count INT;
    v_prov_res JSONB;
BEGIN
    RAISE NOTICE '--- RUNNING SIMULATED TRANSACTION TEST ON SYNTHETIC ORPHAN ---';

    -- 1. Insert synthetic orphan user into auth.users (with trigger disabled momentarily for test isolation if needed, or trigger provisions)
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
        v_test_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'orphan_recovery_sim@example.com', 'dummy_hash', NOW(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Simulated Orphan User"}'::jsonb,
        NOW(), NOW()
    );

    -- If Migration 0016 trigger fired, records already exist. Let's test the recovery script's idempotency!
    -- Run recovery logic for this synthetic user
    v_prov_res := public.internal_provision_workspace(
        p_user_id       => v_test_uid,
        p_name          => 'Simulated Orphan User',
        p_profile_type  => 'ledger',
        p_currency_code => 'INR',
        p_is_default    => TRUE
    );

    v_test_co_id := v_prov_res->>'profile_id';

    -- Verify exactly 1 company owned
    SELECT COUNT(*) INTO v_comp_count FROM public.companies WHERE owner_id = v_test_uid;
    IF v_comp_count <> 1 THEN
        RAISE EXCEPTION 'TEST VERIFICATION FAILED: Expected exactly 1 company for user %, found %', v_test_uid, v_comp_count;
    END IF;

    -- Verify exactly 1 owner membership
    SELECT COUNT(*) INTO v_mem_count FROM public.shared_memberships WHERE account_id = v_test_uid AND role = 'owner';
    IF v_mem_count <> 1 THEN
        RAISE EXCEPTION 'TEST VERIFICATION FAILED: Expected exactly 1 owner membership for user %, found %', v_test_uid, v_mem_count;
    END IF;

    -- Verify 12 canonical ledger accounts
    SELECT COUNT(*) INTO v_acc_count FROM public.accounts WHERE company_id = v_test_co_id AND is_deleted = false;
    IF v_acc_count <> 12 THEN
        RAISE EXCEPTION 'TEST VERIFICATION FAILED: Expected 12 accounts for company %, found %', v_test_co_id, v_acc_count;
    END IF;

    RAISE NOTICE 'TRANSACTIONAL SIMULATION PASSED: Recovery logic successfully validated.';

    -- --------------------------------------------------------------------------
    -- SENTINEL ROLLBACK: Unique SQLSTATE 'P9999' with exact error message
    -- --------------------------------------------------------------------------
    RAISE EXCEPTION 'ROLLBACK_VERIFICATION_COMPLETE' USING ERRCODE = 'P9999';

EXCEPTION
    WHEN OTHERS THEN
        IF SQLSTATE = 'P9999' AND SQLERRM = 'ROLLBACK_VERIFICATION_COMPLETE' THEN
            RAISE NOTICE 'SUCCESS: Verification suite executed all recovery tests successfully and rolled back test records.';
        ELSE
            -- Re-raise unexpected database errors so verification fails genuinely
            RAISE;
        END IF;
END $$;


-- ------------------------------------------------------------------------------
-- 3. POST-RECOVERY HEALTH AUDIT (Run after applying recover_existing_orphaned_accounts.sql)
-- Reports any remaining anomalies across the entire user base.
-- Expected output: 0 rows across all checks.
-- ------------------------------------------------------------------------------

-- Check 3.1: Users in auth.users with 0 companies and 0 memberships
SELECT 
    'UNRESOLVED_ORPHAN' AS anomaly_type,
    u.id AS user_id,
    u.email
FROM auth.users u
LEFT JOIN public.companies c ON c.owner_id = u.id AND c.is_deleted = false
LEFT JOIN public.shared_memberships m ON m.account_id = u.id
GROUP BY u.id, u.email
HAVING COUNT(c.id) = 0 AND COUNT(m.id) = 0;

-- Check 3.2: User profiles with dangling or unowned active_company_id
SELECT 
    'DANGLING_ACTIVE_COMPANY' AS anomaly_type,
    up.id AS profile_id,
    up.email,
    up.active_company_id
FROM public.user_profiles up
LEFT JOIN public.companies c ON c.id = up.active_company_id AND c.is_deleted = false
WHERE up.active_company_id IS NOT NULL 
  AND up.active_company_id <> '' 
  AND up.active_company_id <> 'cmp_default'
  AND c.id IS NULL;

-- Check 3.3: Owned ledger companies with fewer than 12 accounts
SELECT 
    'INCOMPLETE_CHART_OF_ACCOUNTS' AS anomaly_type,
    c.id AS company_id,
    c.name,
    c.owner_id,
    COUNT(a.id) AS accounts_count
FROM public.companies c
LEFT JOIN public.accounts a ON a.company_id = c.id AND a.is_deleted = false
WHERE c.mode = 'ledger' AND c.is_deleted = false AND c.owner_id IS NOT NULL
GROUP BY c.id, c.name, c.owner_id
HAVING COUNT(a.id) < 12;

-- Check 3.4: Duplicate default workspaces (users owning > 1 active workspace where p_is_default was used)
SELECT 
    'MULTIPLE_OWNED_WORKSPACES_AUDIT' AS audit_type,
    c.owner_id,
    COUNT(c.id) AS owned_workspaces_count,
    array_agg(c.id) AS workspace_ids
FROM public.companies c
WHERE c.is_deleted = false AND c.owner_id IS NOT NULL
GROUP BY c.owner_id
HAVING COUNT(c.id) > 1;

