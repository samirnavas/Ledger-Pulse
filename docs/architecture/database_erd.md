# LedgerPulse target ERD

**Status** — Proposed. The [target specification](database_target.md) defines the columns, constraints and authorization rules. The [migration plan](database_migration_plan.md) defines conversion and verification gates. The diagrams use physical table names with schema prefixes where useful.

## Identity, ownership and sharing

```mermaid
erDiagram
    auth_users ||--o| users : "personal record"
    users ||--o{ workspaces : owns
    workspaces ||--o| expense_profiles : "expense configuration"
    workspaces ||--o| ledger_profiles : "business configuration"
    workspaces ||--o{ workspace_memberships : "delegation roster"
    users ||--o{ workspace_memberships : "delegated user"
    workspaces ||--o{ workspace_commits : "ordered change batches"
    users o|--o{ workspace_commits : actor

    users {
        uuid id PK,FK
    }
    workspaces {
        uuid id PK
        uuid owner_user_id FK
        text workspace_type
        bigint revision
        bigint sync_head
    }
    expense_profiles {
        uuid workspace_id PK,FK
        text workspace_type FK
    }
    ledger_profiles {
        uuid workspace_id PK,FK
        text workspace_type FK
    }
    workspace_memberships {
        uuid workspace_id PK,FK
        uuid user_id PK,FK
        text role
        text state
    }
    workspace_commits {
        uuid workspace_id PK,FK
        bigint sequence PK
        uuid operation_id
        uuid actor_user_id FK
    }
```

Auth provisioning establishes a personal row for each onboarded account. The workspace subtype edges form an exclusive pair. At commit, every workspace has exactly one matching subtype. The owner is always one user. A user can own zero or many workspaces and a workspace can have zero or many distinct delegated users. At launch, only ownership grants access. `workspace_commits` is private infrastructure and has an alternate key on workspace plus operation ID.

## Expense

```mermaid
erDiagram
    expense_profiles ||--o{ expense_wallets : contains
    expense_profiles ||--o{ expense_categories : contains
    expense_profiles ||--o{ expense_transactions : contains
    expense_profiles ||--o{ expense_budgets : contains
    expense_profiles ||--o{ expense_recurring_rules : contains
    expense_categories o|--o{ expense_categories : parent
    expense_wallets ||--o{ expense_transactions : source
    expense_wallets o|--o{ expense_transactions : destination
    expense_categories o|--o{ expense_transactions : classifies
    expense_categories o|--o{ expense_budgets : limits
    expense_wallets ||--o{ expense_recurring_rules : "template source"
    expense_wallets o|--o{ expense_recurring_rules : "template destination"
    expense_categories o|--o{ expense_recurring_rules : "template category"
    expense_recurring_rules o|--o{ expense_transactions : generates
```

All Expense relationships use the workspace from the related subtype. A destination wallet is required only for transfers. One rule can generate many transactions over time, with at most one transaction per scheduled date. The NULL-category budget edge represents an overall budget.

## Ledger

```mermaid
erDiagram
    ledger_profiles ||--o{ ledger_parties : contains
    ledger_profiles ||--o{ ledger_accounts : contains
    ledger_profiles ||--o{ ledger_vouchers : contains
    ledger_profiles ||--o{ ledger_journals : contains
    ledger_profiles ||--o{ ledger_inventory_items : contains
    ledger_profiles ||--o{ ledger_audit_events : contains
    ledger_accounts o|--o{ ledger_accounts : parent
    ledger_parties o|--o{ ledger_vouchers : counterparty
    ledger_accounts o|--o{ ledger_vouchers : "settlement source"
    ledger_accounts o|--o{ ledger_vouchers : "settlement destination"
    ledger_accounts o|--o{ ledger_vouchers : classification
    ledger_vouchers o|--o{ ledger_vouchers : "conversion source"
    ledger_vouchers ||--o{ ledger_voucher_lines : documents
    ledger_inventory_items o|--o{ ledger_voucher_lines : "catalog item"
    ledger_vouchers o|--o| ledger_journals : "original posting"
    ledger_journals o|--o| ledger_journals : "reversal link"
    ledger_journals ||--|{ ledger_journal_lines : posts
    ledger_accounts ||--o{ ledger_journal_lines : receives
    ledger_parties o|--o{ ledger_journal_lines : "control dimension"
    ledger_inventory_items ||--o{ ledger_stock_movements : "quantity effects"
    ledger_journals o|--o{ ledger_stock_movements : "associated posting"
    ledger_voucher_lines o|--o{ ledger_stock_movements : "document source"
    ledger_stock_movements o|--o| ledger_stock_movements : "inverse link"
    users o|--o{ ledger_journals : "posting actor"
    users o|--o{ ledger_audit_events : "audit actor"
```

A draft or a non-accounting document can have no original posting. Every posted accounting voucher has exactly one original, with any reversal linked to that journal. A journal can originate outside a voucher. Each committed journal contains two or more balanced lines. A party balance only uses its applicable control-account legs. Voucher lines, journal lines and stock movements also have Ledger subtype FKs. The diagram shows their principal parent edges. Audit subjects are historical references verified at append time.

## Persistence boundary

- PostgreSQL stores authoritative accepted entities, immutable accounting history, audit events and private commit receipts. Supabase Storage holds private binary objects referenced by typed object keys. Object existence, scope and attachment eligibility are validated at assignment time.
- Drift mirrors authorized account and workspace data and the business subset required offline. Device selection, pending work, conflict state and pull checkpoints are local. SQLite projections for balances, party statements or search may be rebuilt from confirmed facts and pending overlays.
