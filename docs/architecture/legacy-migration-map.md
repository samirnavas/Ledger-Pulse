# Legacy Data Migration Mapping & Reconciliation Specification

**Contract Version:** `v1.0.0-PROD-CONTRACT-20261106`  
**Status:** Approved Architectural Target (Read-Only Specification)  
**Strategy:** Strict Non-Destructive Copy, Zero-Loss Preservation, Deterministic Reconciliation  

---

## 1. Migration Principles & Preservation Guarantees

1. **Non-Destructive Dual-Write / Copy:**  
   Existing Expense vouchers and accounts are **copied** into the new dedicated tables (`exp_transactions`, `exp_wallets`, `exp_categories`). Legacy records in `vouchers`, `journals`, `journal_lines`, and `accounts` are **never deleted or modified** during migration. They remain read-only historical records, providing an absolute rollback guarantee.
2. **Deterministic Mode Mapping (No Guessing):**  
   Every existing row in `companies` is mapped to an immutable `profile_type`. If a row has an ambiguous or null `mode`, it is classified strictly using the **Deterministic Evidence Rule** detailed below.
3. **Ban on `repair_legacy_data.sql`:**  
   The script `supabase/repair/repair_legacy_data.sql` contains logic that reassigns all NULL `owner_id` rows to `(SELECT id FROM auth.users ORDER BY created_at ASC LIMIT 1)`. **Execution of this script is strictly prohibited.**

---

## 2. Profile Type Classification & Ambiguity Resolution

When migrating rows from `companies` to the canonical Profile domain model:

```mermaid
flowchart TD
    Start["Existing Company Row"] --> CheckMode{"Is mode explicitly set?"}
    
    CheckMode -->|mode == 'ledger'| SetLedger["ProfileType = 'ledger'"]
    CheckMode -->|mode in ('expense', 'expenseTracker')| SetExpense["ProfileType = 'expense'"]
    
    CheckMode -->|mode IS NULL or empty| InspectData{"Inspect Relational Footprint"}
    
    InspectData -->|Has Parties, Inventory, or Non-Expense Vouchers?| EvidenceLedger["Evidence Rule: ProfileType = 'ledger'"]
    InspectData -->|Only Wallets & Expense Vouchers?| EvidenceExpense["Evidence Rule: ProfileType = 'expense'"]
    InspectData -->|Completely Empty (No Transactions)?| EvidenceEmpty["Default to 'expense' (Safe Personal Mode)"]
    InspectData -->|Contradictory / Unclear Footprint| Quarantine["Mark 'quarantine' & Prompt User"]
```

### 2.1 The Deterministic Evidence Classification Query
```sql
-- Deterministic classification logic for legacy rows with NULL mode
UPDATE public.companies c
SET mode = CASE
    -- 1. Explicit ledger indicators: Has party ledger entries, inventory items, or commercial vouchers
    WHEN EXISTS (SELECT 1 FROM public.parties p WHERE p.company_id = c.id)
      OR EXISTS (SELECT 1 FROM public.inventory_items i WHERE i.company_id = c.id)
      OR EXISTS (SELECT 1 FROM public.vouchers v WHERE v.company_id = c.id AND v.type IN ('sales', 'purchase', 'contra', 'journal'))
    THEN 'ledger'
    
    -- 2. Pure expense tracker indicators: Has vouchers but only of type expense/income/transfer
    WHEN EXISTS (SELECT 1 FROM public.vouchers v WHERE v.company_id = c.id AND v.type IN ('expense', 'income', 'transfer'))
    THEN 'expense'
    
    -- 3. Empty profiles: Default to 'expense'
    ELSE 'expense'
END
WHERE c.mode IS NULL OR c.mode = '';
```

---

## 3. Detailed Table-by-Table Transformation Map

### 3.1 Shared Governance Tables

| Legacy Source Table | Target Physical Table | Transformation / Mapping Logic | Verification Check |
| :--- | :--- | :--- | :--- |
| `companies` | `companies` (`shared_profiles` view) | Retain table in-place. Map `mode = 'expenseTracker'` $\to$ `'expense'`. Backfill `owner_id` via membership link. | `SELECT count(*) FROM companies WHERE mode IS NULL;` must be `0`. |
| `user_profiles` | `user_profiles` (`shared_user_profiles`) | Retain table in-place. Deprecate `companies_json` column (data now lives normalized in `companies`). | `SELECT count(*) FROM user_profiles;` matches pre-migration count. |
| `companies.owner_id` | `shared_memberships` (New) | For every `companies` row where `owner_id IS NOT NULL`, insert `(profile_id, account_id, role) = (c.id, c.owner_id, 'owner')`. | `SELECT count(*) FROM shared_memberships WHERE role = 'owner';` equals owned companies. |

---

### 3.2 Expense Domain Migration Map (Non-Destructive Copy)

#### 3.2.1 Wallets (`accounts` $\to$ `exp_wallets`)
- **Selection Criteria:** `accounts` where `kind = 'wallet'` (or `id LIKE '%_wallet_%'` or `id LIKE '%_acc_wallet_%'`).
- **Target Table:** `exp_wallets`.
- **Field Mapping:**
  ```sql
  INSERT INTO public.exp_wallets (
      id, profile_id, name, wallet_type, currency_code,
      starting_balance_in_cents, current_balance_in_cents,
      is_archived, is_deleted, revision, created_at, updated_at
  )
  SELECT 
      a.id,
      a.company_id,
      a.name,
      CASE 
          WHEN a.code = 'CASH' OR a.name ILIKE '%cash%' THEN 'cash'
          WHEN a.code = 'BANK' OR a.name ILIKE '%bank%' THEN 'bank'
          ELSE 'digital_wallet'
      END,
      'INR',
      0,
      a.current_balance_in_cents,
      NOT a.is_active,
      a.is_deleted,
      a.revision,
      a.created_at,
      a.updated_at
  FROM public.accounts a
  JOIN public.companies c ON c.id = a.company_id
  WHERE (a.kind = 'wallet' OR a.id LIKE '%_wallet_%')
    AND c.mode IN ('expense', 'expenseTracker')
  ON CONFLICT (id) DO NOTHING;
  ```

#### 3.2.2 Categories (`accounts` $\to$ `exp_categories`)
- **Selection Criteria:** `accounts` where `kind = 'category'` (or `type IN ('income', 'expense')` in expense profiles).
- **Target Table:** `exp_categories`.
- **Field Mapping:**
  ```sql
  INSERT INTO public.exp_categories (
      id, profile_id, name, category_type, parent_category_id,
      is_system, is_deleted, revision, created_at, updated_at
  )
  SELECT 
      a.id,
      a.company_id,
      a.name,
      CASE WHEN a.type = 'income' THEN 'income' ELSE 'expense' END,
      a.parent_account_id,
      a.is_system,
      a.is_deleted,
      a.revision,
      a.created_at,
      a.updated_at
  FROM public.accounts a
  JOIN public.companies c ON c.id = a.company_id
  WHERE (a.kind = 'category' OR a.id LIKE '%_acc_cat_%' OR a.type IN ('income', 'expense'))
    AND a.kind <> 'wallet'
    AND c.mode IN ('expense', 'expenseTracker')
  ON CONFLICT (id) DO NOTHING;
  ```

#### 3.2.3 Transactions (`vouchers` $\to$ `exp_transactions`)
- **Selection Criteria:** `vouchers` where `type IN ('expense', 'income', 'transfer')`.
- **Target Table:** `exp_transactions`.
- **Field Mapping:**
  ```sql
  INSERT INTO public.exp_transactions (
      id, profile_id, transaction_type, amount_in_cents,
      wallet_id, to_wallet_id, category_id, transaction_date,
      note, reference_number, receipt_photo_url,
      is_cleared, is_deleted, revision, created_at, updated_at
  )
  SELECT 
      v.id,
      v.company_id,
      v.type,
      v.total_amount_in_cents,
      v.wallet_account_id,
      v.to_wallet_account_id,
      v.category_account_id,
      v.date,
      v.narration,
      v.reference_number,
      v.receipt_photo_url,
      TRUE,
      v.is_deleted,
      v.revision,
      v.created_at,
      v.updated_at
  FROM public.vouchers v
  JOIN public.companies c ON c.id = v.company_id
  WHERE v.type IN ('expense', 'income', 'transfer')
    AND c.mode IN ('expense', 'expenseTracker')
  ON CONFLICT (id) DO NOTHING;
  ```

---

### 3.3 Business Ledger Tables Preservation
All records in `accounts`, `parties`, `ledger_entries`, `vouchers`, `journals`, `journal_lines`, `inventory_items`, `stock_ledger`, and `audit_logs` associated with profiles where `mode = 'ledger'` **remain in their exact current tables**. No data transformation or relocation occurs for Ledger records.

---

## 4. Reconciliation & Verification Queries

To guarantee complete parity before releasing the target schema, the following automated reconciliation checks must execute:

### Check 1: Record Count Integrity
```sql
-- Assert that every expense voucher was copied to exp_transactions
SELECT 
    (SELECT COUNT(*) FROM public.vouchers WHERE type IN ('expense', 'income', 'transfer') AND is_deleted = false) as legacy_expense_count,
    (SELECT COUNT(*) FROM public.exp_transactions WHERE is_deleted = false) as target_expense_count,
    CASE 
        WHEN (SELECT COUNT(*) FROM public.vouchers WHERE type IN ('expense', 'income', 'transfer') AND is_deleted = false) = 
             (SELECT COUNT(*) FROM public.exp_transactions WHERE is_deleted = false)
        THEN 'PASSED' ELSE 'FAILED - COUNT MISMATCH' 
    END as status;
```

### Check 2: Total Financial Value Integrity
```sql
-- Assert that the sum of all transaction amounts matches to the exact cent
SELECT 
    (SELECT COALESCE(SUM(total_amount_in_cents), 0) FROM public.vouchers WHERE type IN ('expense', 'income', 'transfer') AND is_deleted = false) as legacy_total_cents,
    (SELECT COALESCE(SUM(amount_in_cents), 0) FROM public.exp_transactions WHERE is_deleted = false) as target_total_cents,
    CASE 
        WHEN (SELECT COALESCE(SUM(total_amount_in_cents), 0) FROM public.vouchers WHERE type IN ('expense', 'income', 'transfer') AND is_deleted = false) = 
             (SELECT COALESCE(SUM(amount_in_cents), 0) FROM public.exp_transactions WHERE is_deleted = false)
        THEN 'PASSED' ELSE 'FAILED - MONETARY MISMATCH' 
    END as status;
```

### Check 3: Wallet Balance Parity
```sql
-- Assert that current wallet balances match legacy account balances
SELECT 
    a.id as account_id,
    a.current_balance_in_cents as legacy_balance,
    w.current_balance_in_cents as target_balance,
    CASE WHEN a.current_balance_in_cents = w.current_balance_in_cents THEN 'MATCH' ELSE 'DISCREPANCY' END as status
FROM public.accounts a
JOIN public.exp_wallets w ON w.id = a.id
WHERE a.is_deleted = false AND (a.current_balance_in_cents <> w.current_balance_in_cents);
```

---

## 5. Reconstruction of Missing Migrations (0001–0007)

The audit identified that `supabase/migrations/` lacks migrations `0001` through `0007`.

### 5.1 Reconstructible Baseline (Verified from Drift Schema v10)
The complete DDL for base tables can be deterministically reconstructed from the version-controlled Drift schemas and Dart tables:
- `companies` (base fields: id, name, legal_name, currency_code, created_at, updated_at).
- `user_profiles` (id, name, phone_number, email, created_at, updated_at).
- `parties` (id, company_id, name, phone_number, type, net_balance_in_cents).
- `ledger_entries` (id, company_id, party_id, amount_in_cents, type, date).
- `inventory_items` (id, company_id, sku, name, unit, purchase_price, selling_price).
- `stock_ledger` (id, company_id, item_id, voucher_id, transaction_type, quantity).
- `audit_logs` (id, company_id, user_id, entity_type, entity_id, action, checksum).
- `sync_outbox` & `sync_state`.

### 5.2 Required Live Schema Introspection (What Cannot Be Inferred)
Before declaring baseline file `0001_initial_cumulative_schema.sql` definitive, an engineer with authorized live database access must execute:
```sql
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;
```
This guarantees that any production-only triggers, extensions (e.g. `pgcrypto`, `pg_trgm`), or historical indexes added outside Git are faithfully captured.

---
*End of Legacy Data Migration Mapping Specification (`docs/architecture/legacy-migration-map.md`)*

