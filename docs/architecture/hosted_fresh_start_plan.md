# LedgerPulse hosted development cutover

Status as of November 22, 2026. The hosted inventory was rechecked read-only. Application integration and backup rehearsal are open. This draft is for review and is blocked for execution.

## Target and observed state

The app default in `lib/core/config/supabase_config.dart` resolves to `https://awzxwsmfyrbnnuqkxuxu.supabase.co`. Supabase returned that same project reference for **LedgerPulse**, region `ap-south-1`, PostgreSQL 17.6, status `ACTIVE_HEALTHY`. The owner identified this project as disposable development. The most recent recorded hosted migration was `20261121172152_ledger_payment_method`. Neither fresh-start version was in its migration history. `private`, `ledgerpulse_internal`, and the `ledgerpulse-private` bucket were absent.

Read-only catalog results showed five Auth accounts, 57 Expense transactions, 23 journals, and three weekly Expense budgets. The legacy `ledgerpulse_storage` bucket contained zero objects at inspection. The cutover scope includes the 21 application tables named in the SQL below, the `shared_profiles` view, an Auth provisioning trigger, three legacy Storage policies, and 16 legacy application functions. Keep the old bucket metadata, the platform event triggers including `ensure_rls` and its `rls_auto_enable()` function, Auth tables and account IDs, extensions, and existing migration history. `inventory_items` and `stock_ledger` are historically named in the first baseline migration's guard and were absent from the hosted catalog.

## Before requesting approval

1. Finish the Flutter cutover in a separate test environment. The production session controller still reads `profiles`, `user_profiles`, `shared_memberships`, and `companies` at `lib/presentation/providers/profile_session_controller.dart:163–209`. The command sync driver needs a production Drift projection and invocation from the Expense write path. Validate that a command acknowledgement, pull checkpoint, accepted changes and optimistic reconciliation cannot produce duplicate or lost facts after interruption.
2. Finish Expense parity. The additive calendar migration keeps the approved workspace entities and restores weekly budgets, monthly recurrence and yearly recurrence with the existing Dart short-month rule. SQL contract tests cover those cases. Scheduled time of day, budget date/alert semantics, transaction payee fields, attachments and receipt paths still need end-to-end validation. Keep Ledger creation behind Coming Soon.
3. Rehearse with an isolated Supabase copy on PostgreSQL 17. Apply the SQL below, then the two approved baseline files and the additive calendar migration. Verify privileges and dependency behavior, prove both forward and rollback paths, and run the actual Flutter app against the copy. The embedded PostgreSQL 17.5 contract test passed all three files. Hosted DDL privileges, REST exposure, Storage services and Flutter end-to-end operation remain unverified. The local Supabase CLI could not connect to the Windows Docker engine.
4. Freeze legacy test clients and server jobs, capture exact table counts and a restricted account-ID comparison, and recheck the project reference, catalog, migrations, Storage count and backup inventory. Export a consistent, encrypted and access-controlled logical backup covering the `public` schema definitions and data, migration-history evidence, the legacy Auth trigger definition, and the legacy Storage policy definitions and bucket metadata. Verify roles/grants and restore order; use a separate encrypted Storage export if objects appear. Record backup ID or checksum, time, target project and successful isolated restore. Prefer app-scoped restore on the live project so Auth is preserved. [Supabase database backups](https://supabase.com/docs/guides/platform/backups) · [Supabase CLI backup and restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
5. Present the rehearsed operations, current affected inventory, backup verification record, and exact hashes for approval. **Backup status now: no cutover backup confirmed, no restore rehearsal completed.**

## SQL proposed for approval

These statements have only been prepared. Run with stop-on-error and stage the cleanup and all three migrations in one transaction where the hosted execution and migration-history workflow have been rehearsed. Each file contains an outer `begin;` and `commit;`. For that rehearsed single-transaction workflow, stage a temporary wrapper from the checksum-verified sources by removing only their first and final transaction delimiter lines. Keep the migration sources unchanged. Record the three versions using the reviewed migration-history procedure only after successful commit and validation. Treat any new dependency that prevents `RESTRICT` as a reason to abort and review the changed inventory.

```sql
drop trigger trg_on_auth_user_created on auth.users restrict;
drop policy storage_tenant_delete on storage.objects restrict;
drop policy storage_tenant_insert on storage.objects restrict;
drop policy storage_tenant_select on storage.objects restrict;
drop view public.shared_profiles restrict;

drop table public.accounts, public.audit_logs, public.budgets, public.companies,
  public.exp_budgets, public.exp_categories, public.exp_recurring_rules,
  public.exp_transactions, public.exp_wallets, public.journal_lines, public.journals,
  public.ledger_entries, public.parties, public.profiles, public.recurring_rules,
  public.shared_devices, public.shared_memberships, public.sync_outbox,
  public.sync_state, public.user_profiles, public.vouchers restrict;

drop function public.create_workspace_profile(text,text,text,text,text,text),
  public.enforce_profile_type_immutability(), public.get_profile_type(text),
  public.handle_new_user_registration(), public.has_company_role(text,text[]),
  public.has_profile_role(text,text[]),
  public.internal_provision_workspace(uuid,text,text,text,text,text,text,boolean),
  public.invite_profile_member(text,text,text), public.is_company_owner(text),
  public.sync_mutation(text,text,text,jsonb),
  public.sync_mutation_v3(text,text,text,jsonb), public.sync_profile_mode_and_type(),
  public.trg_fn_default_company_profile_id(), public.update_updated_at_and_revision(),
  public.validate_profile_is_expense(), public.validate_profile_is_ledger() restrict;
```

Apply the migration sources under `supabase/fresh-start/supabase/migrations` in this order. SHA-256 values refer to the inspected checkout bytes.

1. `20261121203449_ledgerpulse_schema.sql` — `CFD0F3BF442E07584FD8AC109C6F7809B2B50E7FF96C0F5CC3D8D7400656C5FE`.
2. `20261121203450_ledgerpulse_commands.sql` — `ED5CCEDC3A0A39FC3E47D518426BDB60606A9B2AFB9F2CC0E59524AFB575ECAE`. This installs the new Auth insert trigger and seeds `public.users` from existing Auth IDs. Its Storage statements create the new private bucket and owner-scoped policies.
3. `20261122000000_ledgerpulse_expense_calendar.sql` — `3A62BDF7864F6929DF1DD5F495F2DC73E2FED21BAD40AB89192301AC7C227147`. This changes the existing budget period check and recurrence command. It adds no tables or permissions.

## Device and end-to-end gates

1. Preserve installed Drift databases and pending outboxes by default. For explicitly participating dev devices, use a separate per-account database namespace for the new contract. Inventory pending mutations and retain the old database and its associated write-ahead log as a consistent snapshot. Only clear development app storage with device-specific consent. Select the active workspace locally after confirming the signed-in user's accessible workspace list. Do not replay the legacy queue into the new RPC contract.
2. On the deployed development project compare the original Auth ID set, matching `public.users` bootstrap rows, trigger bindings, migration history, RLS privileges, normalized relations, and Storage scope. Test an existing account signing in, repeated initialization, and a separate account denied access to the first account's workspaces.
3. On the running Expense app test fresh install and legacy install isolation, creation of two workspaces, switch and rename, archive/delete/restore, wallet and category setup, expense/income, transfers and corrections, balance reconciliation, budgets, supported recurring occurrences, and receipt handling. Confirm Ledger creation remains Coming Soon.
4. With two devices, create while offline, restart with pending commands, replay after an interrupted acknowledgement, reconnect in opposite orders, resolve a revision conflict, verify delayed tombstones and restore, and switch accounts and workspaces during sync. Compare hosted rows, operation receipts and device balances. Record the app build, test results, and observed server/client state before declaring the cutover verified.

## Prerequisite verification results

- **Passed in embedded PostgreSQL 17.5.** All three migrations and the database contract executed. A weekly budget round-tripped through the command RPC. January 31 advanced to February 29 and February 29 advanced to February 28 the following year. Replaying either accepted occurrence preserved one transaction and one advancement. The existing receipt-path scope tests also passed with fixture objects.
- **Passed in the Flutter sync harness.** Nine tests cover the normalized RPC envelope, outbox durability, replay after an interrupted acknowledgement, simulated devices, workspace and account switching, conflict reconciliation, and delayed deletion. A regression test proves database serialization failures can retry without marking the queued command permanently rejected.
- **Passed in Flutter analysis and focused tests.** `flutter analyze --no-pub` reported no issues. The focused workspace lifecycle, Expense repository, budget, recurrence, and sync suites passed all 61 tests.
- **Failed in the complete Flutter app suite.** `flutter test --no-pub --reporter expanded` ended with 690 passed, 18 failed, and one skipped. No tests were suppressed. These failures remain a release gate.
- **Still open.** Runtime workspaces and Expense writes still use the legacy app persistence paths. The command sync tests use a fixture replica. There is no production replica or app wiring in this change. Real Flutter-to-Supabase tests, backup verification, and full-schema rehearsal are still required.

## Rollback

The embedded PostgreSQL 17.5 rehearsal applied all three migrations inside one cutover transaction over a minimal legacy fixture. It confirmed that cutover seeded the existing Auth ID and a pre-commit rollback restored the legacy row and removed the target schema changes. A restore of an actual hosted snapshot and the full legacy dependency graph still needs rehearsal.

Before commit, abort the cutover transaction and reopen the legacy dev clients only after verifying their normal reads and writes. After commit, keep clients frozen, retain any normalized data and uploads created since the cutover, and execute the separately reviewed inverse using the rehearsed backup. Restore the legacy application definitions, data, grants, RLS, Storage policies and old Auth trigger, and remove the normalized Auth trigger as part of restoring legacy provisioning. Compare preserved Auth IDs, test the legacy app, then reconcile the recorded migration history with the restored schema. A post-commit rollback that needs to remove normalized objects or overwrite new data requires its own exact approval. Project-wide restore that rewinds Auth is outside this procedure.
