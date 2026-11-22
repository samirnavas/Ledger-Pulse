# Flutter persistence verification

## Scope

This change is an incremental local persistence update. Drift v15 adds category archival metadata and backfills it from matching legacy category accounts in the same workspace. Existing financial rows and databases are retained. Expense category CRUD now uses the Expense category table, including parent validation and archival. The budget repository validates its category against Expense data. Expense transaction creation validates scoped wallets and categories, and repeated transaction IDs cannot apply balance changes twice. Corrections require an active transaction in the current workspace.

Selection is stored in a per-account device preference. The scoped older key remains a migration fallback. Workspace selection no longer generates a user-profile outbox write. The repository supports owner-checked local deletion and restoration while retaining financial rows. The signed-in switcher routes recognized workspace deletions through that repository. Restoration is available through the repository API. A restore screen remains outstanding.

Ledger creation on user-facing creation screens displays **Coming Soon**. Release builds gate entry to the Ledger home while Expense creation stays available. Existing platform styling and internal Ledger repositories are retained.

A debug-only `--dart-define=LEDGERPULSE_DEV_DB_NAMESPACE=workspace-schema` opens a separate local database for intentional clean-start testing. Choose a new namespace to create a fresh database. Clearing the define returns to the original database. This mechanism creates a separate database and leaves existing files intact.

## Modified files

- Drift schema, generation and connection handling — `lib/data/local/database.dart`, `lib/data/local/database.g.dart`, `lib/data/local/connection/connection.dart`, `lib/data/local/connection/native.dart`, `lib/data/local/connection/web.dart`.
- Expense persistence — `lib/data/local/drift_expense_repository.dart`, `lib/data/local/drift_expense_repository_v2.dart`, `lib/data/local/drift_budget_repository.dart`, `lib/data/services/recurring_service.dart`.
- Workspace and account state — `lib/domain/repositories/i_profile_repository.dart`, `lib/presentation/providers/profile_session_controller.dart`, `lib/presentation/providers/company_providers.dart`, `lib/presentation/providers/profile_provider.dart`.
- Release UI — `lib/presentation/auth/app_root_gate.dart`, `lib/presentation/auth/profile_onboarding_screen.dart`, `lib/presentation/home/create_company_flow.dart`.
- Updated tests — `test/architecture/database_architecture_test.dart`, `test/auth/session_initialization_test.dart`, `test/budgets_and_recurring_test.dart`, `test/database_migration_test.dart`, `test/expense_repository_test.dart`, `test/profile/workspace_lifecycle_and_immutability_test.dart`, `test/ui/account_profile_ui_test.dart`.

## Remaining cutover work

The Flutter client still uses the legacy Supabase persistence contract. Mapping personal data to `public.users`, consolidating `profiles` and `companies` into one authoritative workspace model, and switching Ledger persistence to normalized voucher and journal structures remain outstanding. Compatibility rows and model fields are consequently still in use. This work does not verify financial persistence against the new Supabase deployment. The synchronization engine was left unchanged.

## Verification run

- Drift generation completed with `build_runner` filtered to `lib/data/local/database.g.dart`. A second generator run reported zero outputs.
- `flutter analyze --no-pub` reported no issues.
- 119 tests passed across `test/expense_repository_test.dart`, `test/budgets_and_recurring_test.dart`, `test/profile/workspace_lifecycle_and_immutability_test.dart`, `test/database_migration_test.dart`, `test/architecture/database_architecture_test.dart`, `test/drift_ledger_repository_test.dart`, `test/widget_entry_service_test.dart`, and `test/auth/session_initialization_test.dart`.
- All 7 account and onboarding widget tests passed in `test/ui/account_profile_ui_test.dart`.
- Both tests passed in `test/expense/expense_domain_test.dart` and `test/expense/expense_decoupling_test.dart`.
- Android debug APK generation passed. Windows cannot build the iOS target.
