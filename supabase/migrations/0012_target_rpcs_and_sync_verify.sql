-- ====================================================================
-- MIGRATION 0012: VERIFICATION SCRIPT
-- ====================================================================

-- 1. Verify existence of RPC functions with SECURITY DEFINER and search_path
SELECT 
    routine_name, 
    security_type,
    routine_definition ILIKE '%search_path = public%' AS has_safe_search_path
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('create_workspace_profile', 'invite_profile_member', 'sync_mutation_v3');

-- 2. Verify EXECUTE permissions are revoked from PUBLIC and granted to authenticated
SELECT 
    routine_name,
    grantee,
    privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('create_workspace_profile', 'invite_profile_member', 'sync_mutation_v3')
ORDER BY routine_name, grantee;

