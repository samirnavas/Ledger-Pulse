-- SQLite repair for Ledger records accidentally attached to an Expense profile.
-- Bind :source, :destination, :party_count and :entry_count before execution.
-- This preserves record IDs, money values, dates, notes and receipt references.
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
CREATE TEMP TABLE ledger_move_guard (ok INTEGER NOT NULL CHECK (ok = 1));
INSERT INTO ledger_move_guard SELECT CASE WHEN
  EXISTS (SELECT 1 FROM companies WHERE id=:source AND mode IN ('expense','expenseTracker') AND is_deleted=0)
  AND EXISTS (SELECT 1 FROM companies WHERE id=:destination AND mode='ledger' AND is_deleted=0)
  AND (SELECT count(*) FROM parties WHERE company_id=:source)=:party_count
  AND (SELECT count(*) FROM ledger_entries WHERE company_id=:source)=:entry_count
  THEN 1 ELSE 0 END;
CREATE TEMP TABLE ledger_move_parties AS SELECT id FROM parties WHERE company_id=:source;
CREATE TEMP TABLE ledger_move_entries AS SELECT id,amount_in_cents FROM ledger_entries WHERE company_id=:source;
-- Abort rather than leave an entry linked to a party in another workspace.
INSERT INTO ledger_move_guard SELECT CASE WHEN NOT EXISTS (
  SELECT 1 FROM ledger_entries WHERE id IN (SELECT id FROM ledger_move_entries)
    AND party_id NOT IN (SELECT id FROM ledger_move_parties)
) THEN 1 ELSE 0 END;
-- Require every moved row to have its queued mutation available for an atomic rewrite.
INSERT INTO ledger_move_guard SELECT CASE WHEN
  (SELECT count(*) FROM sync_outbox WHERE table_name='parties' AND record_id IN (SELECT id FROM ledger_move_parties))=:party_count
  AND (SELECT count(*) FROM sync_outbox WHERE table_name='ledger_entries' AND record_id IN (SELECT id FROM ledger_move_entries))=:entry_count
  THEN 1 ELSE 0 END;
UPDATE parties SET company_id=:destination, updated_at=CAST(strftime('%s','now') AS INTEGER),
  revision=revision+1,sync_status='pending' WHERE id IN (SELECT id FROM ledger_move_parties);
UPDATE ledger_entries SET company_id=:destination, updated_at=CAST(strftime('%s','now') AS INTEGER),
  revision=revision+1,sync_status='pending' WHERE id IN (SELECT id FROM ledger_move_entries);
UPDATE sync_outbox SET payload=json_set(payload,
    '$.companyId',:destination,'$.company_id',:destination,
    '$.updatedAt',strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    '$.updated_at',strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    '$.revision',(SELECT revision FROM parties WHERE id=sync_outbox.record_id)),
  attempts=0,last_error=NULL,next_attempt_at=NULL
  WHERE table_name='parties' AND record_id IN (SELECT id FROM ledger_move_parties);
UPDATE sync_outbox SET payload=json_set(payload,
    '$.companyId',:destination,'$.company_id',:destination,
    '$.updatedAt',strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    '$.updated_at',strftime('%Y-%m-%dT%H:%M:%fZ','now'),
    '$.revision',(SELECT revision FROM ledger_entries WHERE id=sync_outbox.record_id)),
  attempts=0,last_error=NULL,next_attempt_at=NULL
  WHERE table_name='ledger_entries' AND record_id IN (SELECT id FROM ledger_move_entries);
INSERT INTO ledger_move_guard SELECT CASE WHEN NOT EXISTS (
  SELECT 1 FROM ledger_entries e JOIN ledger_move_entries original ON e.id=original.id
  WHERE e.amount_in_cents<>original.amount_in_cents OR e.company_id<>:destination
) AND NOT EXISTS (SELECT 1 FROM pragma_foreign_key_check)
THEN 1 ELSE 0 END;
COMMIT;
SELECT (SELECT count(*) FROM parties WHERE id IN (SELECT id FROM ledger_move_parties) AND company_id=:destination) AS moved_parties,
  (SELECT count(*) FROM ledger_entries WHERE id IN (SELECT id FROM ledger_move_entries) AND company_id=:destination) AS moved_entries,
  (SELECT sum(amount_in_cents) FROM ledger_entries WHERE id IN (SELECT id FROM ledger_move_entries)) AS preserved_amount_in_cents;
