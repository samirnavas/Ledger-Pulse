-- Verification for Migration 0014
-- Ensure NO public policies exist that allow company owner access or owner_id IS NULL
DO $$
DECLARE
  v_public_policies integer;
BEGIN
  SELECT count(*) INTO v_public_policies
  FROM pg_policies
  WHERE schemaname = 'public' 
    AND (
      'public' = ANY(roles) 
      OR qual LIKE '%owner_id IS NULL%'
      OR policyname = 'Company owner access'
      OR policyname LIKE 'owner_isolation_%'
    );

  IF v_public_policies > 0 THEN
    RAISE EXCEPTION 'Verification failed: Found % permissive or legacy policies remaining', v_public_policies;
  END IF;
  RAISE NOTICE 'Migration 0014 verification PASSED: Zero permissive overlaps found.';
END;
$$;

