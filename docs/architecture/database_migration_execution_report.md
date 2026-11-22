# LedgerPulse Supabase fresh-start execution report

## Result and environment

The Task 2 schema is implemented in a separate [fresh-start Supabase workdir](../../supabase/fresh-start/supabase/config.toml). Its project ID is `ledgerpulse-fresh-start`. The linked or hosted project was never selected as an execution target. The Supabase CLI reported that the Windows Docker engine pipe was unavailable, so no local Supabase service or hosted development target was verified.

Both forward migrations were applied in order to a newly provisioned PGlite PostgreSQL 17.5 instance in process memory. The harness provided minimal Auth and Storage schemas and the `anon` and `authenticated` database roles. It started with zero Auth records and no application tables. There was no pre-existing instance to snapshot or reset. The test fixtures were rolled back and the instance closed. No hosted SQL ran, no existing database was reset, and no Auth users were deleted. This verifies the SQL and database role contracts. Managed Auth, Storage HTTP, PostgREST and Supabase advisors remain unverified.

| Artifact | Result |
| --- | --- |
| [Schema migration](../../supabase/fresh-start/supabase/migrations/20261121203449_ledgerpulse_schema.sql) | Applied successfully on fresh PostgreSQL. Defines UUID identities, scoped foreign keys, workspace subtypes, financial tables and the private feed. Refuses installation alongside named legacy application tables. |
| [Commands and RLS migration](../../supabase/fresh-start/supabase/migrations/20261121203450_ledgerpulse_commands.sql) | Applied successfully. Defines owner-only RLS, Auth provisioning, arguments constrained to the caller and workspace, lifecycle, synchronized entity commands, accounting and reversals, audit, snapshots and Storage policies. |
| [Database contract](../../supabase/fresh-start/supabase/tests/ledgerpulse_database.test.sql) | Passed against PostgreSQL fixtures. Covers repeated initialization and user edits, multiple workspaces, subtype and composite FK rejection, owner isolation, dormant admin membership, direct-write denial, workspace deletion and restoration, idempotent Expense/Journals, journal balance and reversal, stock effects, atomic recurring generation, and Storage paths. |
| [In-memory verifier](../../supabase/fresh-start/verify-postgres.cjs) | Runs migrations and contract against a fresh PostgreSQL instance with no connection URL. Use the pinned `@electric-sql/pglite@0.3.15` package for the verified setup. |

## Reproduction

Use a new isolated local stack named `ledgerpulse-fresh-start` with the ports in its config. Confirm the identity and that the ports and project containers are unused before starting it. A new stack applies only the two forward migrations. Existing isolated stacks require their own review before any destructive action. The historical root `supabase/migrations` stays available for deployed environments.

```powershell
supabase --workdir supabase/fresh-start start
supabase --workdir supabase/fresh-start test db --local
```

The PostgreSQL-only check uses the fixture harness. Its dependency can be installed outside the repo.

```powershell
$verificationDir = Join-Path $env:TEMP "ledgerpulse-db-verification"
npm.cmd install --prefix $verificationDir --no-audit --no-fund @electric-sql/pglite@0.3.15
node supabase/fresh-start/verify-postgres.cjs (Join-Path $verificationDir "node_modules/@electric-sql/pglite")
```

## Obsolete structures excluded from the baseline

- `user_profiles`, `profiles`, `companies`, `shared_memberships`, and `shared_devices`. Typed workspace tables replace identity and business configuration. Owner identity derives from the workspace.
- `exp_wallets`, `exp_categories`, `exp_transactions`, `exp_budgets`, and `exp_recurring_rules` are replaced by typed `expense_*` tables. Legacy `budgets` and `recurring_rules` are also excluded.
- Unscoped legacy definitions of `parties`, `accounts`, `vouchers`, `journals`, `journal_lines`, `inventory_items`, `stock_ledger` and `audit_logs` are replaced by the scoped `ledger_*` tables. `ledger_entries` is replaced by the invoker-safe `ledger_party_activity` projection.
- No old workspace JSON, active-company field, row mutation RPC, cloud outbox or independently synced balance table is included. These exclusions apply only to the new workdir. The historical migration files and deployed schemas were retained.

## Design decisions and remaining verification

- Workspace ownership and type are fixed at creation. A revision-checked command can change currency before creating financial records, including wallet opening amounts. The currency whitelist is INR, USD, EUR and GBP with exponent 2, and JPY with exponent 0. Confirm the launch currency set before client rollout.
- Journals post atomically with explicit balanced lines and validate active targets, party dimensions, scope and voucher totals. Review document-type chart mappings, legal calendar and numbering, accounting period locks, tax rounding, inventory valuation and negative-stock rules before financial production use. Issued numbers use a serialized per-document-type sequence derived from existing numbered records in the fresh baseline. Historical numbering requires a separate strategy.
- Weekly and daily recurrence advancement is implemented. Month/year template storage is supported, and generation is blocked until month-end semantics are approved. Budget period/rollover arithmetic, scheduler ownership, stock costing and tax authority integrations remain product decisions. Direct stock adjustment without a journal records a quantity fact.
- Workspace snapshots are single-response and the private feed retains receipts without an automated pruner. Large workspace snapshot size, two-session concurrent posting and replay, retention, request/batch sizing and advisor checks need a full-stack load rehearsal.
- Supabase development deployment, full Auth signup/Storage API and PostgREST validation still need an independently verified isolated Supabase stack. Storage object cleanup and retention require a separate privileged process. No legacy schema upgrade or cleanup was applied. Flutter still targets legacy contracts until separately migrated.

References for the full-stack rehearsal are the [Supabase CLI guide](https://supabase.com/docs/guides/local-development/cli/getting-started) and [RLS guide](https://supabase.com/docs/guides/database/postgres/row-level-security).
