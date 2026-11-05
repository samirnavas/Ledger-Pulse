-- ====================================================================
-- VERIFICATION SCRIPT FOR MIGRATION 0009
-- ====================================================================

-- 1. Verify owner_id and kind columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'companies'
  AND column_name = 'owner_id';

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'accounts'
  AND column_name = 'kind';

-- 2. Verify unique index on sync_outbox
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'sync_outbox'
  AND indexname = 'sync_outbox_table_record_idx';

-- 3. Verify RLS is enabled on companies and parties
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('companies', 'parties', 'ledger_entries', 'user_profiles');
