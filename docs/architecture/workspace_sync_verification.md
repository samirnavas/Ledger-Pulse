# LedgerPulse workspace synchronization

**Status** — The normalized transport and durable command driver are implemented and exercised in tests. The installed Flutter app still uses the legacy sync provider. Task 4 left its repositories and Drift projections on the legacy persistence contract. The normalized driver requires a typed Drift projection and repository integration before activation. Running both protocols against the same financial rows would require an explicit cutover design.

## Data flow and boundaries

1. A repository supplies a workspace UUID, a stable operation UUID, a named command and its JSON envelope. The local optimistic edit and immutable outbox entry commit in one Drift transaction. The normalized driver creates two local-only infrastructure tables lazily and preserves the legacy schema and outbox. These tables store commands, receipts and checkpoints. The typed financial projection belongs to the application repository.
2. The selected workspace and current authenticated user are captured at the start of the run. The user must match the account-scoped Drift file. An account change, workspace change, expired session or token refresh invalidates in-flight work before applying its response. A command already accepted on the server can still commit. The client recovers it by replaying its operation ID when the authorized session resumes.
3. Push sends an immutable command to the Task 3 RPC. Commands are processed in creation order within a workspace. A retry with the same operation ID and payload reconciles against the original receipt. Conflicts block that workspace's remaining unaccepted commands until explicitly resolved. Connection failures leave the same command eligible for the next sync.
4. Pull requests an ordered sequence feed. Each batch is validated and applied with its checkpoint in one SQLite transaction. A bad scope or sequence rolls back the batch. JSON object order is irrelevant to snapshot ordering. The projection adapter must enforce typed foreign keys, apply tree relationships in dependency order, and defer notifications until transaction commit.
5. When a confirmed sequence includes an accepted command, the projection removes its optimistic overlay in the same transaction. The local receipt remains to prevent accidental duplicate local application of a completed intent. A snapshot reconciles accepted commands covered by its head. A deleted or inaccessible workspace clears its confirmed projection, retains user-owned recovery work and requires a fresh snapshot on return.
6. Transfers use one Expense transaction command. Ledger posting, reversal and replacement submit one command each. The server commits the journal, lines, any applicable stock and audit effects together. The driver consumes that whole batch. Posted balances should derive from confirmed rows, while any optimistic accounting display must remain separately identified until confirmation.

The Supabase transport calls `ledgerpulse_create_workspace`, `ledgerpulse_command`, `ledgerpulse_pull` and `ledgerpulse_snapshot`. It uses ordinary authenticated RPCs and does not require a privileged client credential. The checked-in server functions remain the authority for scoping, revisions and financial invariants. [Supabase Flutter RPC reference](https://supabase.com/docs/reference/dart/rpc)

## Conflict and deletion rules

| Change | Resolution |
| --- | --- |
| Workspace name, currency, lifecycle and settings | Server checks the revision of the specific workspace or subtype. Stop on a stale edit. Review confirmed settings and resubmit intended changes under their current revision and a new operation ID. Currency and lifecycle restrictions still apply. |
| Wallets, categories and budgets | Use expected revisions and scoped references. A retry never rewrites an accepted intent. Resolve archived references, uniqueness or conflicting edits explicitly. Do not recreate an archived or tombstoned reference implicitly. |
| Expense transactions and transfers | One record identity and operation per intent. Updates, deletes and restores require the current revision. Stale writes leave accepted amounts and tombstones intact. Both transfer effects follow the same accepted row. |
| Ledger posting and financial corrections | Post only through journal or document commands. Corrections use the server's atomic reversal or reversal/replacement. Replays return the same receipt. Invalid replacements leave the original posting and head unchanged. |
| Deletion and restoration | Keep row tombstones in the projection, and exclude them from active balances and lists. Only an explicit fresh restore may clear them. The workspace deletion state evicts confirmed financial data locally and invalidates its cursor. Scope the sole hard-delete wire event, a draft voucher-line removal, to the selected workspace. |
| Network or session loss | Leave unsent and unacknowledged commands durable. Redeliver their original payload after reconnect. Retry and conflict resolution are separate. No financial last-write-wins fallback in the normalized path. |

## Changed services and tests

- [Workspace command sync engine and gateway](../../lib/core/network/workspace_sync_engine.dart) contain the durable outbox, checkpoint and scope-validated batch driver. `WorkspaceReplica` is the transaction-bound integration point for typed Drift repositories.
- [Legacy sync engine](../../lib/core/network/sync_engine.dart) checks incoming and existing local scopes before applying rows or tombstones. Real Supabase sync suspends unless its session matches the account partition.
- [Native Drift connection](../../lib/data/local/connection/native.dart) leaves the oldest unscoped database file in place for verified recovery. It no longer adopts that file based on a row count or on an inspection failure.
- [Flutter sync contract tests](../../test/sync/workspace_command_sync_test.dart) exercise durable commands and transactional projection with independent Drift/SQLite stores and a controlled gateway.
- [PostgreSQL contract](../../supabase/fresh-start/supabase/tests/ledgerpulse_database.test.sql) also exercises a stale update competing with a tombstone, an invalid correction that rolls back, and retrying a valid atomic correction. It runs against a disposable PostgreSQL 17.5 harness with Supabase schema fixtures. No hosted data was used.
- Updated legacy regression fixtures in `test/database/reactive_database_selection_test.dart`, `test/supabase_outbox_sync_test.dart`, `test/sync_modes_and_vouchers_test.dart` and `test/sync/timestamp_regression_test.dart` match the existing schema and financial correction behavior. The native isolation test verifies that an unscoped file remains intact and unavailable from another account's database.

## Executed verification

- 134 Flutter tests passed across `test/sync`, `test/supabase_outbox_sync_test.dart`, `test/sync_modes_and_vouchers_test.dart`, `test/database/reactive_database_selection_test.dart` and `test/device_auth_persistence_test.dart`.
- The PostgreSQL 17.5 contract passed with both fresh-start migrations applied in memory.
- The SDK transport test verified the RPC names, scoped arguments and lossless decimal cursor encoding against mocked HTTP.
- Flutter analysis reported no issues across the changed Dart files.

## Activation and remaining risk

- The current app has no normalized typed replica or repository command producers wired. Its legacy row-upsert path still has the previously audited atomicity and last-write-wins limitations. This change avoids automatically translating legacy queued rows into financial commands.
- Test evidence uses simulated devices with independent SQLite stores and an isolated PostgreSQL contract harness. It does not cover live multi-device Supabase operation, PostgREST transport under network interruption, or simultaneous database sessions.
- Production activation needs checkpoint versioning across dataset resets, an approved receipt/retention policy, backoff scheduling, user-facing conflict resolution, scoped cache cleanup on discovery, and a supported migration path for legacy pending work. The current normalized driver runs on demand. A blocked command needs an explicit discard or new intent. Local receipt history currently has no pruning policy.
