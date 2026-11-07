-- ====================================================================
-- MIGRATION 0012: ROLLBACK SCRIPT
-- ====================================================================

DROP FUNCTION IF EXISTS public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.invite_profile_member(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.sync_mutation_v3(TEXT, TEXT, TEXT, JSONB);

