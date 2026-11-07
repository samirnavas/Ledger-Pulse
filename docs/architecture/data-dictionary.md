# Comprehensive Data Dictionary & Column Specification

**Contract Version:** `v1.0.0-PROD-CONTRACT-20261106`  
**Status:** Approved Architectural Target (Read-Only Specification)  
**Standard Currency Precision:** 64-bit Signed Integer (`BIGINT`) representing minor currency units (cents / paise). Zero floating-point money.  
**Standard Inventory Precision:** Fixed decimal `NUMERIC(14, 4)` representing physical unit quantities (e.g. `12.5000` kg).  

---

## 1. Domain Types & Enumerations

| Enumeration Name | Target PostgreSQL Definition | Allowed String Literals | Dart Enum Equivalent |
| :--- | :--- | :--- | :--- |
| `ProfileType` | `TEXT CHECK (val IN ('expense', 'ledger'))` | `'expense'`, `'ledger'` | `enum ProfileType { expense, ledger }` |
| `MembershipRole` | `TEXT CHECK (val IN ('owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer'))` | `'owner'`, `'admin'`, `'accountant'`, `'manager'`, `'data_entry'`, `'viewer'` | `enum MembershipRole { owner, admin, accountant, manager, dataEntry, viewer }` |
| `SyncStatus` | `TEXT CHECK (val IN ('synced', 'pending', 'error'))` | `'synced'`, `'pending'`, `'error'` | `enum SyncRecordStatus { synced, pending, error }` |
| `ExpenseTxnType` | `TEXT CHECK (val IN ('expense', 'income', 'transfer'))` | `'expense'`, `'income'`, `'transfer'` | `enum ExpenseTransactionType { expense, income, transfer }` |
| `ExpenseWalletType`| `TEXT CHECK (val IN ('cash', 'bank', 'credit_card', 'digital_wallet', 'savings'))` | `'cash'`, `'bank'`, `'credit_card'`, `'digital_wallet'`, `'savings'` | `enum WalletType { cash, bank, creditCard, digitalWallet, savings }` |
| `LedgerAccountType`| `TEXT CHECK (val IN ('asset', 'liability', 'equity', 'income', 'expense'))` | `'asset'`, `'liability'`, `'equity'`, `'income'`, `'expense'` | `enum AccountType { asset, liability, equity, income, expense }` |
| `LedgerVoucherType`| `TEXT CHECK (val IN ('sales', 'purchase', 'receipt', 'payment', 'contra', 'journal', 'salesOrder', 'purchaseOrder', 'estimate'))` | `'sales'`, `'purchase'`, `'receipt'`, `'payment'`, `'contra'`, `'journal'`, `'salesOrder'`, `'purchaseOrder'`, `'estimate'` | `enum VoucherType { sales, purchase, receipt, payment, contra, journal, salesOrder, purchaseOrder, estimate }` |
| `LedgerVoucherStatus`| `TEXT CHECK (val IN ('draft', 'posted', 'voided'))` | `'draft'`, `'posted'`, `'voided'` | `enum VoucherStatus { draft, posted, voided }` |
| `PartyType` | `TEXT CHECK (val IN ('customer', 'supplier'))` | `'customer'`, `'supplier'` | `enum PartyType { customer, supplier }` |
| `AuditAction` | `TEXT CHECK (val IN ('insert', 'update', 'void', 'delete'))` | `'insert'`, `'update'`, `'void'`, `'delete'` | `enum AuditAction { insert, update, voidAction, delete }` |

---

## 2. Shared Governance Tables

### 2.1 `shared_profiles` (Physical Table: `public.companies`)
*Multi-tenant workspace container. Maps 1:1 with existing `companies` table to eliminate migration risk.*

| Column Name | PostgreSQL Type | Drift / Dart Type | Nullable | Default | PK/FK / Constraints | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `TextColumn` / `String` | No | None | `PRIMARY KEY` | Globally unique profile identifier (e.g. `prf_01H...` or legacy `cmp_...`). |
| `name` | `TEXT` | `TextColumn` / `String` | No | None | None | Display name of the workspace or business. |
| `legal_name` | `TEXT` | `TextColumn` / `String` | No | None | None | Registered legal entity name (for invoices and tax). |
| `mode` | `TEXT` | `TextColumn` / `String` | No | `'ledger'` | `CHECK (mode IN ('expense', 'expenseTracker', 'ledger'))` | **Immutable Profile Type**. Legacy `'expenseTracker'` maps to canonical `'expense'`. |
| `owner_id` | `UUID` | `TextColumn` / `String` | Yes | `auth.uid()` | `FK -> auth.users(id)` | Creator / primary billing account owner. |
| `currency_code` | `TEXT` | `TextColumn` / `String` | No | `'INR'` | `CHECK (currency_code ~ '^[A-Z]{3}$')` | ISO-4217 standard 3-letter currency symbol. |
| `gstin` | `TEXT` | `TextColumn` / `String` | Yes | None | `CHECK (gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$')` | Indian 15-character Goods and Services Taxpayer Identification Number. |
| `state_code` | `TEXT` | `TextColumn` / `String` | Yes | None | `CHECK (length(state_code) = 2)` | 2-digit Indian GST statutory state code (e.g. `'07'` for Delhi). |
| `dealer_type` | `TEXT` | `TextColumn` / `String` | No | `'regular'` | `CHECK (dealer_type IN ('regular', 'composition', 'unregistered'))` | Statutory GST taxation classification. |
| `address` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Registered operational/billing street address. |
| `email` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Business / support contact email. |
| `phone_number` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Primary contact telephone or mobile number. |
| `logo_url` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Storage URL or relative path to business brand mark. |
| `signature_url`| `TEXT` | `TextColumn` / `String` | Yes | None | None | Storage URL or relative path to authorized signatory graphic. |
| `signatory_name`| `TEXT`| `TextColumn` / `String` | Yes | None | None | Printed name of authorized signatory for formal invoices. |
| `bank_name` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Name of bank where business settlement account resides. |
| `bank_account_number` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Bank account number printed on sales invoices. |
| `bank_ifsc` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Indian Financial System Code for electronic clearing. |
| `upi_id` | `TEXT` | `TextColumn` / `String` | Yes | None | None | UPI Virtual Payment Address (VPA) for dynamic invoice QR codes. |
| `is_cloud_sync_enabled` | `BOOLEAN` | `BoolColumn` / `bool` | No | `TRUE` | None | Flag controlling cloud synchronization participation. |
| `is_active` | `BOOLEAN` | `BoolColumn` / `bool` | No | `TRUE` | None | Active / suspended tenant state flag. |
| `enabled_modules` | `JSONB` | `TextColumn` / `String` | Yes | None | None | Enabled feature module array (e.g. `["inventory", "gst"]`). |
| `revision` | `BIGINT` | `IntColumn` / `int` | No | `0` | None | Concurrency tracking revision number. |
| `is_deleted` | `BOOLEAN` | `BoolColumn` / `bool` | No | `FALSE` | None | Soft-delete status flag. |
| `created_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Record creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Last mutation timestamp (used for sync cursor). |

---

### 2.2 `shared_memberships` (New Table)
*Maps accounts to workspace profiles with granular RBAC.*

| Column Name | PostgreSQL Type | Drift / Dart Type | Nullable | Default | PK/FK / Constraints | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `UUID` | `TextColumn` / `String` | No | `gen_random_uuid()` | `PRIMARY KEY` | Unique membership identifier. |
| `profile_id` | `TEXT` | `TextColumn` / `String` | No | None | `FK -> companies(id) ON DELETE CASCADE` | Target workspace profile. |
| `account_id` | `UUID` | `TextColumn` / `String` | No | None | `FK -> auth.users(id) ON DELETE CASCADE` | Associated authenticated user account. |
| `role` | `TEXT` | `TextColumn` / `String` | No | None | `CHECK (role IN ('owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer'))` | RBAC role governing permitted actions in workspace. |
| `joined_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Timestamp membership was established. |
| `updated_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Timestamp role or status was modified. |

---

## 3. Dedicated Expense Domain Tables

### 3.1 `exp_wallets`
*Cash, bank, credit card, and digital payment instruments.*

| Column Name | PostgreSQL Type | Drift / Dart Type | Nullable | Default | PK/FK / Constraints | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `TextColumn` / `String` | No | None | `PRIMARY KEY` | Wallet identifier (e.g. `wal_01H...`). |
| `profile_id` | `TEXT` | `TextColumn` / `String` | No | None | `FK -> companies(id) ON DELETE CASCADE` | Parent workspace profile. |
| `name` | `TEXT` | `TextColumn` / `String` | No | None | None | Wallet name (e.g. "Main HDFC Bank", "Cash Pocket"). |
| `wallet_type` | `TEXT` | `TextColumn` / `String` | No | `'cash'` | `CHECK (wallet_type IN ('cash', 'bank', 'credit_card', 'digital_wallet', 'savings'))` | Instrument type. |
| `currency_code`| `TEXT` | `TextColumn` / `String` | No | `'INR'` | `CHECK (currency_code ~ '^[A-Z]{3}$')` | Currency unit for this specific wallet. |
| `starting_balance_in_cents` | `BIGINT` | `IntColumn` / `int` | No | `0` | None | Opening balance in minor units (cents / paise). |
| `current_balance_in_cents` | `BIGINT` | `IntColumn` / `int` | No | `0` | None | Denormalized running balance in minor units. |
| `color_hex` | `TEXT` | `TextColumn` / `String` | Yes | None | None | UI accent color code (e.g. `'#006C4C'`). |
| `icon_name` | `TEXT` | `TextColumn` / `String` | Yes | None | None | UI iconography token (e.g. `'account_balance'`). |
| `is_archived` | `BOOLEAN` | `BoolColumn` / `bool` | No | `FALSE` | None | Soft-archival flag hiding wallet from active pickers. |
| `is_deleted` | `BOOLEAN` | `BoolColumn` / `bool` | No | `FALSE` | None | Soft-delete flag. |
| `revision` | `BIGINT` | `IntColumn` / `int` | No | `0` | None | Concurrency revision. |
| `created_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Last update timestamp. |

---

### 3.2 `exp_categories`
*Single-entry classification for expenses and revenues.*

| Column Name | PostgreSQL Type | Drift / Dart Type | Nullable | Default | PK/FK / Constraints | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `TextColumn` / `String` | No | None | `PRIMARY KEY` | Category identifier (e.g. `cat_01H...`). |
| `profile_id` | `TEXT` | `TextColumn` / `String` | No | None | `FK -> companies(id) ON DELETE CASCADE` | Parent workspace profile. |
| `name` | `TEXT` | `TextColumn` / `String` | No | None | None | Category title (e.g. "Groceries", "Salary"). |
| `category_type`| `TEXT` | `TextColumn` / `String` | No | `'expense'` | `CHECK (category_type IN ('expense', 'income'))` | Directionality of fund flow. |
| `parent_category_id` | `TEXT` | `TextColumn` / `String` | Yes | None | `FK -> exp_categories(id) ON DELETE SET NULL` | Hierarchical sub-category grouping link. |
| `icon_name` | `TEXT` | `TextColumn` / `String` | Yes | None | None | UI iconography symbol token. |
| `color_hex` | `TEXT` | `TextColumn` / `String` | Yes | None | None | UI color representation. |
| `is_system` | `BOOLEAN` | `BoolColumn` / `bool` | No | `FALSE` | None | System-seeded default category protection flag. |
| `is_deleted` | `BOOLEAN` | `BoolColumn` / `bool` | No | `FALSE` | None | Soft-delete flag. |
| `revision` | `BIGINT` | `IntColumn` / `int` | No | `0` | None | Concurrency revision. |
| `created_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Last update timestamp. |

---

### 3.3 `exp_transactions`
*Single-entry atomic transaction ledger.*

| Column Name | PostgreSQL Type | Drift / Dart Type | Nullable | Default | PK/FK / Constraints | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id` | `TEXT` | `TextColumn` / `String` | No | None | `PRIMARY KEY` | Transaction identifier (e.g. `txn_01H...`). |
| `profile_id` | `TEXT` | `TextColumn` / `String` | No | None | `FK -> companies(id) ON DELETE CASCADE` | Parent workspace profile. |
| `transaction_type` | `TEXT` | `TextColumn` / `String` | No | None | `CHECK (transaction_type IN ('expense', 'income', 'transfer'))` | Nature of transaction. |
| `amount_in_cents` | `BIGINT` | `IntColumn` / `int` | No | None | `CHECK (amount_in_cents > 0)` | Absolute value in minor units (cents / paise). |
| `wallet_id` | `TEXT` | `TextColumn` / `String` | No | None | `FK -> exp_wallets(id) ON DELETE RESTRICT` | Source wallet (disbursed or credited). |
| `to_wallet_id` | `TEXT` | `TextColumn` / `String` | Yes | None | `FK -> exp_wallets(id) ON DELETE RESTRICT` | Destination wallet (Required for `transfer`). |
| `category_id` | `TEXT` | `TextColumn` / `String` | Yes | None | `FK -> exp_categories(id) ON DELETE RESTRICT` | Spending/revenue category (income/expense only). |
| `transaction_date` | `TIMESTAMPTZ`| `DateTimeColumn` | No | None | None | Effective date and time of transaction. |
| `note` | `TEXT` | `TextColumn` / `String` | Yes | None | None | User remarks or narrative memo. |
| `payee_or_payer` | `TEXT` | `TextColumn` / `String` | Yes | None | None | Third party merchant or client name. |
| `reference_number` | `TEXT`| `TextColumn` / `String` | Yes | None | None | Cheque number, UTR, or invoice reference. |
| `receipt_photo_url`| `TEXT`| `TextColumn` / `String` | Yes | None | None | Storage path or URL to photographed receipt bill. |
| `is_cleared` | `BOOLEAN` | `BoolColumn` / `bool` | No | `TRUE` | None | Reconciliation / bank clearance status. |
| `is_deleted` | `BOOLEAN` | `BoolColumn` / `bool` | No | `FALSE` | None | Soft-delete flag. |
| `revision` | `BIGINT` | `IntColumn` / `int` | No | `0` | None | Concurrency revision. |
| `created_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | `DateTimeColumn` | No | `NOW()` | None | Last update timestamp. |

---

## 4. Preserved Business Ledger Domain Tables

The Business Ledger tables (`companies`, `accounts`, `parties`, `ledger_entries`, `vouchers`, `journals`, `journal_lines`, `inventory_items`, `stock_ledger`, `audit_logs`) maintain their complete structural integrity.

### 4.1 Key Ledger Fields & Accounting Semantics
1. **`vouchers.total_amount_in_cents`:** `BIGINT NOT NULL DEFAULT 0`. Must equal:
   $$\text{subtotal\_in\_cents} + \text{tax\_in\_cents} - \text{discount\_in\_cents} \pm \text{round\_off\_in\_cents}$$
2. **`journal_lines.debit_in_cents` & `credit_in_cents`:** `BIGINT NOT NULL DEFAULT 0`. Mutually exclusive positive integers:
   $$\text{debit\_in\_cents} \ge 0 \quad \text{AND} \quad \text{credit\_in\_cents} \ge 0 \quad \text{AND} \quad (\text{debit} = 0 \lor \text{credit} = 0)$$
3. **`inventory_items.current_stock_quantity`:** `NUMERIC(14, 4) NOT NULL DEFAULT 0.0000`. Updated strictly by appending transactions to `stock_ledger`.
4. **`audit_logs.checksum`:** `TEXT NOT NULL`. Verified by:
   $$\text{SHA-256}(\text{id} \parallel \text{company\_id} \parallel \text{user\_id} \parallel \text{action} \parallel \text{timestamp} \parallel \text{newStateJson} \parallel \text{previousChecksum})$$

---
*End of Comprehensive Data Dictionary (`docs/architecture/data-dictionary.md`)*

