-- ==============================================================================
-- SCRIPT: IDENTIFY ORPHANED SUPABASE ACCOUNTS (READ-ONLY AUDIT & CLASSIFICATION)
-- Target: LedgerPulse Supabase / PostgreSQL (Schemas: auth, public)
-- Purpose: Safely inspects all registered auth.users, cross-references application
--          tables, and classifies each account into actionable recovery categories.
-- Security: Read-only query. Strictly excludes passwords, hashes, and auth tokens.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- STEP 1: Create session-scoped temporary view encapsulating classification logic
-- ------------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW v_orphaned_accounts_audit AS
WITH user_summary AS (
    SELECT 
        u.id AS user_id,
        u.email,
        u.created_at AS user_created_at,
        u.last_sign_in_at,
        u.email_confirmed_at IS NOT NULL AS is_email_confirmed,
        
        -- User Profiles
        up.id IS NOT NULL AS has_user_profile,
        up.name AS profile_name,
        up.active_company_id,

        -- Companies owned
        COUNT(DISTINCT c_owned.id) AS owned_companies_count,
        COALESCE(MAX(c_owned.id), NULL) AS first_owned_company_id,
        COALESCE(MAX(c_owned.mode), NULL) AS first_owned_company_mode,

        -- Memberships
        COUNT(DISTINCT m.id) AS total_memberships_count,
        COUNT(DISTINCT m.id) FILTER (WHERE m.role = 'owner') AS owner_memberships_count,

        -- Accounts count in the primary/first owned company
        COUNT(DISTINCT a.id) AS default_company_accounts_count,

        -- Check if active_company_id exists and is valid
        EXISTS (
            SELECT 1 FROM public.companies c_act 
            WHERE c_act.id = up.active_company_id AND c_act.is_deleted = false
        ) AS is_active_company_valid,

        -- Check for presence of unassigned/corrupted NULL owner companies matching user
        EXISTS (
            SELECT 1 FROM public.companies c_null
            JOIN public.shared_memberships sm_null ON sm_null.profile_id = c_null.id
            WHERE sm_null.account_id = u.id AND c_null.owner_id IS NULL
        ) AS has_null_owner_company_conflict

    FROM auth.users u
    LEFT JOIN public.user_profiles up ON up.id = u.id::text OR up.owner_id = u.id
    LEFT JOIN public.companies c_owned ON c_owned.owner_id = u.id AND c_owned.is_deleted = false
    LEFT JOIN public.shared_memberships m ON m.account_id = u.id
    LEFT JOIN public.accounts a ON a.company_id = c_owned.id AND a.is_deleted = false
    GROUP BY u.id, u.email, u.created_at, u.last_sign_in_at, u.email_confirmed_at, up.id, up.name, up.active_company_id
),
classified_users AS (
    SELECT 
        s.*,
        CASE
            -- 1. Ambiguous or corrupted states requiring human architectural review
            WHEN s.has_null_owner_company_conflict THEN 
                'REQUIRES_MANUAL_INVESTIGATION: NULL owner company linked to membership'

            -- 2. Fully Provisioned: User profile exists, owns >= 1 active workspace, holds owner role, has active company, and has >= 12 accounts
            WHEN s.has_user_profile 
             AND s.owned_companies_count >= 1 
             AND s.owner_memberships_count >= 1
             AND s.is_active_company_valid
             AND s.default_company_accounts_count >= 12 THEN 
                'FULLY_PROVISIONED'

            -- 3. Complete Orphan: Registered in auth.users but has NO workspace and NO memberships
            WHEN s.owned_companies_count = 0 AND s.total_memberships_count = 0 THEN 
                'ELIGIBLE_COMPLETE_ORPHAN'

            -- 4. Missing User Profile Only: Workspace, membership, and accounts exist, but user_profiles row is absent
            WHEN NOT s.has_user_profile 
             AND s.owned_companies_count >= 1 
             AND s.owner_memberships_count >= 1 THEN 
                'ELIGIBLE_MISSING_PROFILE_ONLY'

            -- 5. Missing Owner Membership: Company exists with owner_id = user, but shared_memberships row is missing
            WHEN s.owned_companies_count >= 1 
             AND s.owner_memberships_count = 0 THEN 
                'ELIGIBLE_MISSING_MEMBERSHIP_ONLY'

            -- 6. Missing Accounts Only: Company and membership exist, but standard 12 accounts are incomplete
            WHEN s.has_user_profile 
             AND s.owned_companies_count >= 1 
             AND s.owner_memberships_count >= 1 
             AND s.default_company_accounts_count < 12 THEN 
                'ELIGIBLE_MISSING_ACCOUNTS_ONLY'

            -- 7. Inconsistent Active Company: Profile exists but active_company_id is NULL or references missing/deleted company
            WHEN s.has_user_profile 
             AND s.owned_companies_count >= 1 
             AND (s.active_company_id IS NULL OR s.active_company_id = 'cmp_default' OR NOT s.is_active_company_valid) THEN 
                'INCONSISTENT_ACTIVE_WORKSPACE'

            -- 8. Invited Collaborator Only: Holds non-owner membership in another company and has 0 owned companies
            WHEN s.owned_companies_count = 0 AND s.total_memberships_count > 0 AND s.owner_memberships_count = 0 THEN
                'INVITED_COLLABORATOR_NO_OWNED_WORKSPACE'

            ELSE 
                'REQUIRES_MANUAL_INVESTIGATION: Unclassified anomaly'
        END AS recovery_category,

        CASE
            WHEN s.has_null_owner_company_conflict THEN
                'Do not auto-provision. Investigate historical ownership and link manually.'
            WHEN s.has_user_profile AND s.owned_companies_count >= 1 AND s.owner_memberships_count >= 1 AND s.is_active_company_valid AND s.default_company_accounts_count >= 12 THEN
                'No action required. Account is in healthy state.'
            WHEN s.owned_companies_count = 0 AND s.total_memberships_count = 0 THEN
                'Auto-recover via internal_provision_workspace(p_user_id, is_default => true).'
            WHEN NOT s.has_user_profile AND s.owned_companies_count >= 1 AND s.owner_memberships_count >= 1 THEN
                'Create user_profiles record and link active_company_id to existing owned company.'
            WHEN s.owned_companies_count >= 1 AND s.owner_memberships_count = 0 THEN
                'Insert owner membership in shared_memberships for verified owned company.'
            WHEN s.has_user_profile AND s.owned_companies_count >= 1 AND s.owner_memberships_count >= 1 AND s.default_company_accounts_count < 12 THEN
                'Seed missing default accounts into existing company.'
            WHEN s.has_user_profile AND s.owned_companies_count >= 1 AND (s.active_company_id IS NULL OR s.active_company_id = 'cmp_default' OR NOT s.is_active_company_valid) THEN
                'Update user_profiles.active_company_id to point to first_owned_company_id.'
            WHEN s.owned_companies_count = 0 AND s.total_memberships_count > 0 AND s.owner_memberships_count = 0 THEN
                'Invited member. Preserve access to shared workspace. Provision personal default workspace only if requested.'
            ELSE
                'Manual inspection required before executing any mutation.'
        END AS recommended_action
    FROM user_summary s
)
SELECT * FROM classified_users;

-- ------------------------------------------------------------------------------
-- STEP 2: DETAILED TABULAR AUDIT (Renders in Supabase SQL Editor results grid)
-- ------------------------------------------------------------------------------
SELECT 
    user_id,
    email,
    user_created_at,
    last_sign_in_at,
    has_user_profile,
    profile_name,
    active_company_id,
    owned_companies_count,
    first_owned_company_id,
    first_owned_company_mode,
    total_memberships_count,
    owner_memberships_count,
    default_company_accounts_count,
    recovery_category,
    COUNT(*) OVER (PARTITION BY recovery_category) AS total_users_in_category,
    recommended_action
FROM v_orphaned_accounts_audit
ORDER BY user_created_at ASC;
