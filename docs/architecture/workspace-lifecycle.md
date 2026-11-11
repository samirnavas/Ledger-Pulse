# LedgerPulse Workspace Lifecycle & Profile Immutability Specification

**Document Version:** `v1.1.0-PROD-LIFECYCLE-20261111`  
**Status:** Approved Canonical Specification  
**Authority:** LedgerPulse Architecture Board  
**Target Environments:** Android (Material 3 Expressive), iOS (iOS 27 Cupertino), Desktop, Web  

---

## 1. Domain Disambiguation: Account Identity vs. Workspace Identity

LedgerPulse strictly separates user credentials and global account identity from workspace/tenant identity:

```
+-------------------------------------------------------------------------------+
|                             Account (`auth.users`)                            |
|       Globally unique authenticated identity (email / phone / password / OTP) |
+-------------------------------------------------------------------------------+
                                       |
                   +-------------------+-------------------+
                   | 1:1                                   | 1:N
                   v                                       v
+------------------------------------+   +------------------------------------+
|  User Profile (`user_profiles`)    |   |  Membership (`shared_memberships`)  |
|  Display name, email, avatar, etc. |   |  account_id, profile_id, role      |
+------------------------------------+   +------------------------------------+
                                                           |
                                                           | N:1
                                                           v
                                         +------------------------------------+
                                         | Workspace Profile (`companies`)    |
                                         | IMMUTABLE TYPE: `expense` | `ledger`|
                                         +------------------------------------+
```

- **Account (`auth.users`)**: The authenticated subject authenticated via Supabase Auth (`auth.uid()`). An account possesses authentication tokens, credentials, and user settings. An account does **not** directly own ledger vouchers or personal expense transactions.
- **User Profile (`user_profiles` / `shared_user_profiles`)**: Stores user-scoped metadata (display name, email, avatar) 1:1 with the Account.
- **Workspace Profile (`companies` / `shared_profiles`)**: The autonomous tenant data boundary containing either personal expense records (`exp_*`) or business double-entry books (`led_*`).
- **Membership (`shared_memberships`)**: Relational link joining an Account to a Workspace Profile with a specific role (`owner`, `admin`, `accountant`, `manager`, `data_entry`, `viewer`).

---

## 2. Canonical Workspace Lifecycle

The authoritative lifecycle is orchestrated exclusively by `ProfileSessionController` (`profileSessionProvider`), returning state modeled by `ProfileSessionState`:

```
               +--------------------------------------+
               |          Application Launch          |
               +--------------------------------------+
                                  |
                   Is session authenticated?
                   /                      \
             No   /                        \  Yes
                 v                          v
    +-------------------------+   +------------------------------------+
    |  GuestReadySessionState |   |  ProfileSessionController:         |
    |  (Routes to Auth Gate)  |   |  syncAndLoadRemoteWorkspaces(uid)  |
    +-------------------------+   +------------------------------------+
                                            |
                               How many accessible profiles?
                               /            |            \
                          0   /          1  |             \  > 1
                             v              v              v
        +-------------------------+  +-------------+  +--------------------------+
        |   OnboardingRequired    |  | Auto-select |  | Saved preference valid?  |
        |  SessionState (Prompt   |  | lone profile|  | (last_active_profile_uid)|
        |  to create workspace)   |  +-------------+  +--------------------------+
        +-------------------------+         |             /                  \
                                            |       Yes  /                    \  No
                                            v           v                      v
                                  +-----------------------+     +--------------------------+
                                  |  ActiveProfileReady   |     | ProfileSelectionRequired |
                                  |  SessionState (Binds  |     | SessionState (Renders    |
                                  |  scoped repositories) |     | ProfileSelectorScreen)   |
                                  +-----------------------+     +--------------------------+
```

### Lifecycle Steps
1. **Unauthenticated User**: `GuestReadySessionState` is established. The app renders authentication gates; no tenant databases or workspace repositories are unlocked.
2. **Authentication**: Upon successful credential verification, `ProfileSessionController.loadProfilesForUser(userId)` queries local `shared_memberships` and pulls cloud workspaces from Supabase via `IProfileRepository.syncAndLoadRemoteWorkspaces(userId)`.
3. **Zero Accessible Workspaces**: If the account has no valid memberships, the state transitions to `OnboardingRequiredSessionState(userId)`. The user is guided through `ProfileOnboardingScreen`. The system **never** silently creates a default or dummy workspace.
4. **Single Accessible Workspace**: If exactly one accessible workspace is returned, it is automatically activated (`ActiveProfileReadySessionState`).
5. **Multiple Accessible Workspaces**:
   - The controller checks for a persisted active workspace preference scoped to the account: `last_active_profile_$userId` (falling back to legacy `last_active_company_id_$userId`).
   - If the saved workspace ID corresponds to an accessible profile in the account's membership list, it is restored into `ActiveProfileReadySessionState`.
   - If no saved preference exists or the saved workspace is inaccessible/deleted, the controller transitions to `ProfileSelectionRequiredSessionState`, prompting the user to choose in `ProfileSelectorScreen`.
6. **Active Workspace**: The application binds workspace-scoped providers (`activeCompanyIdProvider`, `companyRepositoryProvider`, `ledgerRepositoryProvider`). Data queries are partition-scoped to the active `profile_id`.
7. **Account Switch / Logout**: `ProfileSessionController.logout()` invalidates the session and transitions to `GuestReadySessionState`. Account-scoped preferences prevent previous workspace state from leaking into subsequent logins by different accounts.

---

## 3. Strict Workspace Type Immutability

Each workspace profile has a fixed, immutable `mode` / `ProfileType`:
- `expense`: Personal or freelance expense cashbook.
- `ledger`: Double-entry business ledger with statutory accounts, GST, and audit trails.

### Immutability Rules
1. **Never Mutate**: An `expense` workspace **cannot** be upgraded or converted to a `ledger` workspace. A `ledger` workspace cannot be converted to `expense`.
2. **Local Database Protection**: `DriftCompaniesProfileMixin.updateCompany()` validates that incoming updates match the existing `mode`. If a mismatch is detected, it throws `UnsupportedError`. The underlying SQL update sets `mode: Value(existing.mode)` as a permanent invariant.
3. **Domain Model Protection**: `Company.copyWith()` throws `StateError` if a caller attempts to alter `mode`.
4. **Remote Sync Protection**: When remote pulls apply company updates (`SyncEngine` and `DriftProfileRepository`), any existing local `mode` is strictly preserved. Remote data cannot silently overwrite workspace types.
5. **Creation of Separate Workspace**: Users who require business accounting functionality while maintaining personal expense tracking are directed to create a separate Business Ledger workspace via the canonical creation flow.

---

## 4. Supported Creation and Switching Flows

### 4.1 Canonical Creation Flow
All workspace creations funnel through `IProfileRepository.createProfile()`:
```dart
Future<WorkspaceProfileHeader> createProfile({
  required String name,
  required ProfileType type,
  String currencyCode = 'INR',
  String? legalName,
  String? gstin,
  String? stateCode,
  String? dealerType,
  Set<AppModule>? enabledModules,
  Map<String, int>? initialWalletBalancesInCents,
  String? customId,
  String? accountId,
});
```

- **`ProfileOnboardingScreen`**: Direct invocation of `IProfileRepository.createProfile()` or `CompanyController.addCompany()`.
- **`CreateCompanyFlow`**: Collects module choices, GST details, state code, and initial cash/bank opening balances, passing them directly to `CompanyController.addCompany()` -> `IProfileRepository.createProfile()`.
- **Atomic Initialization**:
  - Atomically creates the `companies` record with immutable `mode`.
  - Atomically seeds the Chart of Accounts (`postingEngine.seedAccountsFor()`).
  - For `expense` workspaces, seeds default wallets (Cash, Bank) and categories (Food, Transport, Utilities, etc.).
  - Atomically creates an `owner` membership in `shared_memberships`.
  - Enqueues sync outbox mutations to push the workspace and membership to Supabase.
  - Updates the active profile session in `ProfileSessionController`.

### 4.2 Workspace Switching Flow
- **Entry Points**: `CompanySwitcherSheet` (Home & Ledger) and `ExpenseSidebarDrawer` (Expense).
- **Execution**: Invokes `ProfileSessionController.switchActiveProfile(profileId)` and `CompanyController.switchCompany(profileId)`.
- **Session Rebinding**: Updates Riverpod state, rebinds workspace-scoped providers, and notifies the UI hierarchy without requiring an application restart.
- **Persistence**: Persists `last_active_profile_$userId` in `SharedPreferences`.

---

## 5. Legacy Compatibility Paths Retained

To guarantee zero data loss and avoid disruption to existing installations, the following legacy compatibility paths are intentionally retained:

| Compatibility Path | Reason Retained | Retirement Condition |
| :--- | :--- | :--- |
| **`companies` Table Name** | Physical SQLite and PostgreSQL tables use `companies` rather than `shared_profiles`. | Can be renamed to `shared_profiles` only after a phased cloud migration and local schema version bump. |
| **`cmp_default` Fallback in `DriftLedgerRepository`** | Required when tests or guest unauthenticated flows initialize local Drift repositories before a profile session is active. | Can be retired once all guest interactions are 100% mocked or prevented from touching disk. |
| **`companies_json` Import Support** | `DriftCompaniesProfileMixin.syncFromUserProfile()` preserves legacy JSON blob migration for offline databases upgrading from v1. | Retained until all active devices have synchronized beyond version 1.x. |
| **`last_active_company_id_$userId` Preference Fallback** | Backward compatibility with saved user preferences from previous app releases. | Reads legacy key if `last_active_profile_$userId` is absent, then writes the canonical key. |
| **`0015_post_observation_legacy_cleanup.sql.pending_approval`** | Intentionally **NOT** executed. Awaiting full production observation window and sign-off. | Execute only after cloud verification confirms zero references to obsolete RPCs and legacy columns. |

---

## 6. Obsolete Methods Retired

The following obsolete methods and anti-patterns have been completely removed:

1. **`CompanyController.bootstrapInitialProfile()`**: Removed. Bypassed the profile session controller and risked creating duplicate default workspaces.
2. **`CompanyController.ensureProfileAndCompanyExist()`**: Removed. Silently created dummy workspaces upon arbitrary screen access.
3. **`CompanyController.upgradeToLedger()`**: Removed. Violated workspace immutability by altering `company.mode` in place.
4. **`DriftCompaniesProfileMixin.upgradeToLedger()`**: Removed. Direct database mutation path that converted expense companies to ledger.
5. **`SettingsScreen.showUpgradeDialog()`**: Replaced with `showCreateBusinessLedgerDialog()`, explaining immutability and routing to canonical creation flow.
6. **Silent Dummy Row Seeding in `DriftLedgerRepository._seedIfEmpty`**: Restricted strictly to `_currentCompanyId == 'cmp_default'`, eliminating silent generation of phantom company records.

