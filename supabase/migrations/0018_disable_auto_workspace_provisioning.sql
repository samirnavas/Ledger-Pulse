-- ====================================================================
-- SUPABASE MIGRATION 0018: DISABLE AUTOMATIC WORKSPACE PROVISIONING ON REGISTRATION
-- Target: LedgerPulse Supabase / PostgreSQL
-- Purpose: Stop automatic creation of default ledger workspaces and accounts on auth signup.
--          Users now explicitly configure their workspace (mode, name, currency) on onboarding.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_full_name TEXT;
    v_workspace_name TEXT;
BEGIN
    -- 1. Extract Full Name from raw_user_meta_data candidates
    v_full_name := COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(NEW.raw_user_meta_data->>'user_name'), '')
    );

    -- 2. Derive User Display Name:
    IF v_full_name IS NULL THEN
        IF NEW.email IS NOT NULL AND TRIM(NEW.email) <> '' AND POSITION('@' IN NEW.email) > 1 THEN
            v_workspace_name := INITCAP(REPLACE(SPLIT_PART(TRIM(NEW.email), '@', 1), '.', ' '));
        ELSE
            v_workspace_name := 'User';
        END IF;
        v_full_name := COALESCE(NULLIF(TRIM(v_workspace_name), ''), 'User');
    END IF;

    -- 3. Provision user_profiles record atomically (user account details only, NO implicit workspace)
    INSERT INTO public.user_profiles (
        id,
        name,
        email,
        phone_number,
        business_name,
        role,
        owner_id,
        active_company_id,
        created_at,
        updated_at,
        sync_status,
        revision
    ) VALUES (
        NEW.id::text,
        v_full_name,
        COALESCE(TRIM(NEW.email), ''),
        COALESCE(TRIM(NEW.phone), ''),
        '',
        'admin',
        NEW.id,
        '',
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

    RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user_registration() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user_registration() TO postgres, service_role;

-- Clean up any legacy guest/placeholder profile records that may have been synced
UPDATE public.profiles SET is_deleted = true WHERE id = 'cmp_default';

