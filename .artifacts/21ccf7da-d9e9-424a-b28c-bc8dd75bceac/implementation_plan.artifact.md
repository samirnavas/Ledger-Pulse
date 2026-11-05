# Phase 3 Implementation Plan - Per-User Isolation & Scoped Architecture

This document outlines the technical implementation plan for **Phase 3: Per-User Isolation** in Ledger-Pulse (Flutter, Drift, Supabase).

## User Review Required

> [!IMPORTANT]
> - **Per-User Database Files**: Each logged-in user will have a dedicated SQLite file named `ledger_pulse_<uid>.sqlite` (`ledger_pulse_<uid>` on Web).
> - **Legacy Migration**: On first login after the update, if a legacy `ledger_pulse.sqlite` exists and exactly one user has ever logged in, it will automatically migrate to `ledger_pulse_<uid>.sqlite`.
> - **Scoped Repositories & Shared Update Stream**: `ledgerRepositoryProvider` and `driftLedgerRepositoryProvider` will be collapsed into a single provider scoped to `(uid, activeCompanyId)`. Both `DriftLedgerRepository` and `DriftExpenseRepository` will share a single update stream to eliminate stale UI state across views.
> - **Cascading Company Soft-Delete**: Deleting a company soft-deletes the `companies` row and all child rows (`parties`, `entries`, `vouchers`, `accounts`, `journals`, `journal_lines`, `budgets`, `recurring_rules`, `inventory_items`, `stock_ledger`) in a single transaction, setting `syncStatus = pending` and enqueuing outbox mutations.

---

## Proposed Changes

### Component 1: Database & Connection Layer

#### [MODIFY] [native.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/connection/native.dart)
#### [MODIFY] [web.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/connection/web.dart)
#### [MODIFY] [unsupported.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/connection/unsupported.dart)
#### [MODIFY] [connection.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/connection/connection.dart)
- Update `openConnection(String uid)` to generate database connection pointing to `ledger_pulse_<uid>.sqlite` on native (and `'ledger_pulse_<uid>'` on web).
- Implement legacy database migration helper:
  - Checks if `ledger_pulse_<uid>.sqlite` exists.
  - If not, checks for legacy `ledger_pulse.sqlite`.
  - If legacy DB exists, opens it briefly to count user profiles:
    - If exactly 1 user profile exists, renames `ledger_pulse.sqlite` to `ledger_pulse_<uid>.sqlite`.

#### [MODIFY] [database.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/database.dart)
- Add `ownerId` / `owner_id` column (`TextColumn get ownerId => text().named('owner_id').nullable()()`) to `Companies` table.
- Update `AppDatabase` constructor to accept `String uid` and call `impl.openConnection(uid)`.

---

### Component 2: Identity & Repository Default Removal

#### [MODIFY] [i_auth_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/domain/repositories/i_auth_repository.dart)
#### [MODIFY] [supabase_auth_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/repositories/supabase_auth_repository.dart)
- Expose `currentUserId` (`auth.currentUser?.id ?? cachedUserId`).

#### [MODIFY] [drift_ledger_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/drift_ledger_repository.dart)
#### [MODIFY] [drift_expense_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/drift_expense_repository.dart)
#### [MODIFY] [drift_budget_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/drift_budget_repository.dart)
#### [MODIFY] [recurring_service.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/services/recurring_service.dart)
#### [MODIFY] [drift_voucher_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/drift_voucher_repository.dart)
#### [MODIFY] [drift_inventory_repository.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/drift_inventory_repository.dart)
- Remove default constructor values `'usr_default'` and `'cmp_default'`. Require `currentCompanyId` and `currentUserId` explicitly across all repositories.

---

### Component 3: Providers & Scoped Repositories

#### [MODIFY] [database_providers.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/presentation/providers/database_providers.dart)
- `appDatabaseProvider` depends on `uid` from `authRepositoryProvider.currentUserId`.
- When `uid` changes or on logout, old `AppDatabase` is closed and new `AppDatabase(uid)` is initialized.

#### [MODIFY] [ledger_providers.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/presentation/providers/ledger_providers.dart)
- Collapse `driftLedgerRepositoryProvider` and `ledgerRepositoryProvider` into ONE scoped provider keyed by `(uid, activeCompanyId)`.
- Share a single `StreamController<void>` update stream between `DriftLedgerRepository` and `DriftExpenseRepository`.

#### [MODIFY] [profile_provider.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/presentation/providers/profile_provider.dart)
- `UserProfileNotifier.build()` derives `uid` from current authenticated user (`ref.watch(authRepositoryProvider).currentUserId`).
- Key active company in SharedPreferences per user: `last_active_company_id_<uid>`.

---

### Component 4: Company Management & Cascading Soft-Delete

#### [MODIFY] [drift_companies_profile_mixin.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/data/local/drift_companies_profile_mixin.dart)
- In `createCompany`: set `ownerId = currentUserId` and default mode chosen by user (`expenseTracker` or `ledger`).
- Enforce subscription tier `maxCompanies` limit.
- In `deleteCompany`: perform cascading soft-delete in a single `db.transaction`:
  - `companies`: `isDeleted = true`, `syncStatus = pending`, `updatedAt = now`.
  - Soft-delete all child rows for `companyId` in `parties`, `ledger_entries`, `vouchers`, `accounts`, `journals`, `journal_lines`, `budgets`, `recurring_rules`, `inventory_items`, `stock_ledger`, `audit_logs`.
  - Enqueue mutation for each affected row in `sync_outbox`.
- Fix `_deriveAndSyncUserProfileCompaniesJson`: update only current user's profile row (`id = currentUserId`) and mark `syncStatus = pending`.

---

### Component 5: Owner-Isolated Sync Engine

#### [MODIFY] [sync_engine.dart](file:///C:/Programming/app/Ledger%20Pulse/lib/core/network/sync_engine.dart)
- Add `currentUserId` property to `SyncEngine`.
- In `pullChanges`: filter pulled rows for `companies` and `user_profiles` to only rows where `owner_id == currentUserId` or `id == currentUserId`.

---

## Verification Plan

### Automated Tests
1. **Per-User Isolation Unit & Integration Test (`test/sync/phase3_unit_tests.dart`)**:
   - Log in as User A (`usr_a`), create 2 company profiles (1 expenseTracker, 1 ledger).
   - Log out as User A.
   - Log in as User B (`usr_b`). Assert User B sees 0 companies/profiles.
   - Log back in as User A. Assert both profiles and data are intact in `ledger_pulse_usr_a.sqlite`.
   - Verify switching companies never mixes parties, wallets, or vouchers.
   - Verify cascading soft-delete marks company and all child rows as `isDeleted == true` with `syncStatus == pending`.
2. **Run Full Test Suite**: `flutter test`
3. **Run Static Analysis**: `flutter analyze`
