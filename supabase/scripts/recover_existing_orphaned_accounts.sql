-- ==============================================================================
-- SCRIPT: RECOVER EXISTING ORPHANED SUPABASE ACCOUNTS
-- Target: LedgerPulse Supabase / PostgreSQL (Schemas: auth, public)
-- Purpose: Atomically and idempotently provisions missing user profiles,
--          default Ledger workspaces, owner memberships, and canonical accounts
--          for verified orphaned users registered prior to Migration 0016.
-- Architecture: Reuses public.internal_provision_workspace() from Migration 0016.
-- Safety: Fully transactional, idempotent, non-destructive. Never deletes data,
--         never resets balances, never adopts unverified NULL-owner workspaces.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Initialize session-scoped temporary table for recovery audit logging
-- ------------------------------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS temp_account_recovery_log (
    user_id UUID,
    email TEXT,
    action_taken TEXT,
    workspace_id TEXT,
    details TEXT,
    processed_at TIMESTAMPTZ DEFAULT NOW()
);
TRUNCATE TABLE temp_account_recovery_log;

-- ------------------------------------------------------------------------------
-- 2. Execute Transactional Recovery
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
    v_full_name TEXT;
    v_workspace_name TEXT;
    v_existing_owned_co TEXT;
    v_existing_co_mode TEXT;
    v_prov_res JSONB;
    v_target_co_id TEXT;
    v_action_taken TEXT;
    v_has_profile BOOLEAN;
    v_active_co_id TEXT;
    v_is_active_co_valid BOOLEAN;
    v_accounts_count INT;
    v_memberships_count INT;
    v_owner_memberships_count INT;
    v_has_null_conflict BOOLEAN;
    
    -- Counter metrics for summary reporting
    v_count_inspected INT := 0;
    v_count_provisioned INT := 0;
    v_count_repaired INT := 0;
    v_count_skipped_healthy INT := 0;
    v_count_skipped_manual INT := 0;
BEGIN
    RAISE NOTICE '=== STARTING RECOVERY OF ORPHANED SUPABASE ACCOUNTS ===';

    -- Iterate through all users in auth.users ordered by registration date
    FOR r IN 
        SELECT 
            u.id, 
            u.email, 
            u.raw_user_meta_data,
            u.phone,
            u.created_at
        FROM auth.users u
        ORDER BY u.created_at ASC
    LOOP
        v_count_inspected := v_count_inspected + 1;
        v_action_taken := NULL;

        -- 1. Check for ambiguous NULL-owner company linked to this user's memberships
        SELECT EXISTS (
            SELECT 1 FROM public.companies c_null
            JOIN public.shared_memberships sm_null ON sm_null.profile_id = c_null.id
            WHERE sm_null.account_id = r.id AND c_null.owner_id IS NULL
        ) INTO v_has_null_conflict;

        IF v_has_null_conflict THEN
            v_count_skipped_manual := v_count_skipped_manual + 1;
            INSERT INTO temp_account_recovery_log (user_id, email, action_taken, workspace_id, details)
            VALUES (r.id, r.email, 'SKIPPED_MANUAL_REVIEW', NULL, 'User linked to unowned/corrupted company with NULL owner_id. Excluded from automatic recovery.');
            CONTINUE;
        END IF;

        -- 2. Inspect existing profile and active company status
        SELECT 
            id IS NOT NULL,
            active_company_id
        INTO v_has_profile, v_active_co_id
        FROM public.user_profiles
        WHERE id = r.id::text OR owner_id = r.id
        LIMIT 1;

        v_has_profile := COALESCE(v_has_profile, FALSE);

        -- 3. Check for existing companies owned by this user
        SELECT id, mode
        INTO v_existing_owned_co, v_existing_co_mode
        FROM public.companies
        WHERE owner_id = r.id AND is_deleted = false
        ORDER BY created_at ASC
        LIMIT 1;

        -- 4. Check memberships count
        SELECT 
            COUNT(*),
            COUNT(*) FILTER (WHERE role = 'owner')
        INTO v_memberships_count, v_owner_memberships_count
        FROM public.shared_memberships
        WHERE account_id = r.id;

        -- 5. Check accounts count in owned company
        IF v_existing_owned_co IS NOT NULL THEN
            SELECT COUNT(*) INTO v_accounts_count
            FROM public.accounts
            WHERE company_id = v_existing_owned_co AND is_deleted = false;
        ELSE
            v_accounts_count := 0;
        END IF;

        -- 6. Check if active_company_id is valid
        IF v_active_co_id IS NOT NULL AND v_active_co_id <> '' AND v_active_co_id <> 'cmp_default' THEN
            SELECT EXISTS (
                SELECT 1 FROM public.companies WHERE id = v_active_co_id AND is_deleted = false
            ) INTO v_is_active_co_valid;
        ELSE
            v_is_active_co_valid := FALSE;
        END IF;

        -- ----------------------------------------------------------------------
        -- CLASSIFICATION & IDEMPOTENT RECOVERY BRANCHES
        -- ----------------------------------------------------------------------

        -- CASE A: User is already fully provisioned and healthy
        IF v_has_profile 
           AND v_existing_owned_co IS NOT NULL 
           AND v_owner_memberships_count >= 1 
           AND v_is_active_co_valid 
           AND v_accounts_count >= 12 THEN
            
            v_count_skipped_healthy := v_count_skipped_healthy + 1;
            INSERT INTO temp_account_recovery_log (user_id, email, action_taken, workspace_id, details)
            VALUES (r.id, r.email, 'SKIPPED_ALREADY_HEALTHY', v_existing_owned_co, 'User profile, owned workspace, owner membership, and 12 canonical accounts already intact.');
            CONTINUE;
        END IF;

        -- CASE B: Invited collaborator with non-owner membership and no owned workspace
        IF v_existing_owned_co IS NULL AND v_memberships_count > 0 AND v_owner_memberships_count = 0 THEN
            v_count_skipped_manual := v_count_skipped_manual + 1;
            INSERT INTO temp_account_recovery_log (user_id, email, action_taken, workspace_id, details)
            VALUES (r.id, r.email, 'SKIPPED_INVITED_COLLABORATOR', NULL, 'User has membership in shared workspace but owns no company. Preserved existing collaborator access.');
            CONTINUE;
        END IF;

        -- ----------------------------------------------------------------------
        -- RECOVERY EXECUTION: User is eligible for repair
        -- ----------------------------------------------------------------------

        -- 7. Extract full name and derive workspace name using Migration 0016 rules
        v_full_name := COALESCE(
            NULLIF(TRIM(r.raw_user_meta_data->>'full_name'), ''),
            NULLIF(TRIM(r.raw_user_meta_data->>'name'), ''),
            NULLIF(TRIM(r.raw_user_meta_data->>'user_name'), '')
        );

        IF v_full_name IS NOT NULL THEN
            v_workspace_name := v_full_name;
        ELSIF r.email IS NOT NULL AND TRIM(r.email) <> '' AND POSITION('@' IN r.email) > 1 THEN
            v_workspace_name := INITCAP(REPLACE(SPLIT_PART(TRIM(r.email), '@', 1), '.', ' '));
            IF v_workspace_name IS NULL OR TRIM(v_workspace_name) = '' THEN
                v_workspace_name := 'My Ledger';
            END IF;
        ELSE
            v_workspace_name := 'My Ledger';
        END IF;

        IF v_full_name IS NULL THEN
            v_full_name := COALESCE(NULLIF(TRIM(v_workspace_name), ''), 'User');
        END IF;

        -- 8. Backfill / ensure user_profiles record exists without overwriting existing data
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
            r.id::text,
            v_full_name,
            COALESCE(TRIM(r.email), ''),
            COALESCE(TRIM(r.phone), ''),
            v_workspace_name,
            'admin',
            r.id,
            COALESCE(r.created_at, NOW()),
            NOW(),
            'synced',
            0
        ) ON CONFLICT (id) DO UPDATE SET
            name = CASE 
                WHEN public.user_profiles.name IS NULL OR TRIM(public.user_profiles.name) = '' 
                THEN EXCLUDED.name 
                ELSE public.user_profiles.name 
            END,
            email = CASE 
                WHEN public.user_profiles.email IS NULL OR TRIM(public.user_profiles.email) = '' 
                THEN EXCLUDED.email 
                ELSE public.user_profiles.email 
            END,
            phone_number = CASE 
                WHEN public.user_profiles.phone_number IS NULL OR TRIM(public.user_profiles.phone_number) = '' 
                THEN EXCLUDED.phone_number 
                ELSE public.user_profiles.phone_number 
            END,
            owner_id = COALESCE(public.user_profiles.owner_id, EXCLUDED.owner_id),
            updated_at = NOW();

        -- 9. Provision Workspace via Migration 0016 shared engine
        -- If user already owns a company, pass that company ID as p_custom_id so it repairs
        -- memberships and missing accounts without creating a duplicate company!
        IF v_existing_owned_co IS NOT NULL THEN
            v_prov_res := public.internal_provision_workspace(
                p_user_id       => r.id,
                p_name          => v_workspace_name,
                p_profile_type  => COALESCE(v_existing_co_mode, 'ledger'),
                p_currency_code => 'INR',
                p_legal_name    => v_workspace_name,
                p_gstin         => NULL,
                p_custom_id     => v_existing_owned_co,
                p_is_default    => FALSE
            );
            v_target_co_id := v_existing_owned_co;
            v_count_repaired := v_count_repaired + 1;
            v_action_taken := 'REPAIRED_EXISTING_WORKSPACE';
        ELSE
            -- Complete orphan: Create fresh default ledger workspace and accounts
            v_prov_res := public.internal_provision_workspace(
                p_user_id       => r.id,
                p_name          => v_workspace_name,
                p_profile_type  => 'ledger',
                p_currency_code => 'INR',
                p_legal_name    => v_workspace_name,
                p_gstin         => NULL,
                p_custom_id     => NULL,
                p_is_default    => TRUE
            );
            v_target_co_id := v_prov_res->>'profile_id';
            v_count_provisioned := v_count_provisioned + 1;
            v_action_taken := 'PROVISIONED_DEFAULT_WORKSPACE';
        END IF;

        -- 10. Update active_company_id if missing or pointing to invalid default
        IF v_target_co_id IS NOT NULL THEN
            UPDATE public.user_profiles
            SET active_company_id = v_target_co_id
            WHERE id = r.id::text
              AND (active_company_id IS NULL OR active_company_id = '' OR active_company_id = 'cmp_default' OR NOT v_is_active_co_valid);
        END IF;

        -- Log recovery action
        INSERT INTO temp_account_recovery_log (user_id, email, action_taken, workspace_id, details)
        VALUES (
            r.id, 
            r.email, 
            v_action_taken, 
            v_target_co_id, 
            format('Action: %s. Provider result: %s', v_action_taken, v_prov_res::text)
        );

    END LOOP;

    RAISE NOTICE '=== RECOVERY COMPLETE ===';
    RAISE NOTICE 'Users Inspected: %', v_count_inspected;
    RAISE NOTICE 'Workspaces Provisioned (Complete Orphans): %', v_count_provisioned;
    RAISE NOTICE 'Workspaces Repaired (Existing Incomplete): %', v_count_repaired;
    RAISE NOTICE 'Users Already Healthy (Skipped): %', v_count_skipped_healthy;
    RAISE NOTICE 'Users Requiring Manual Review (Skipped): %', v_count_skipped_manual;

END $$;

-- ------------------------------------------------------------------------------
-- 3. AUDIT TRAIL REPORT: View all recovery actions performed
-- ------------------------------------------------------------------------------
SELECT 
    user_id,
    email,
    action_taken,
    workspace_id,
    details,
    processed_at
FROM temp_account_recovery_log
ORDER BY processed_at ASC;
