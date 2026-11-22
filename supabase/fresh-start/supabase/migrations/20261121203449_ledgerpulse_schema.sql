begin;

-- This migration belongs to the isolated fresh-start workdir.
-- Refuse to install alongside legacy application tables.
do $$
begin
  if exists (
    select 1 from pg_catalog.pg_tables
    where schemaname = 'public' and tablename in (
      'companies','profiles','user_profiles','shared_memberships','shared_devices',
      'accounts','parties','vouchers','journals','journal_lines','ledger_entries',
      'inventory_items','stock_ledger','audit_logs','budgets','recurring_rules',
      'exp_wallets','exp_categories','exp_transactions','exp_budgets','exp_recurring_rules'
    )
  ) then
    raise exception 'LedgerPulse fresh-start baseline requires an empty application schema';
  end if;
end $$;

create schema private;
revoke all on schema private from public, anon, authenticated;
create schema ledgerpulse_internal;
revoke all on schema ledgerpulse_internal from public, anon, authenticated;

create table public.users (
  id uuid primary key references auth.users(id),
  display_name text not null check (btrim(display_name) <> ''),
  avatar_object_key text,
  locale text,
  theme_preference text check (theme_preference in ('system','light','dark')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0)
);

create table public.workspaces (
  id uuid primary key,
  owner_user_id uuid not null references public.users(id),
  workspace_type text not null check (workspace_type in ('expense','ledger')),
  name text not null check (btrim(name) <> ''),
  currency_code text not null check (currency_code in ('INR','USD','EUR','GBP','JPY')),
  lifecycle_state text not null default 'active',
  archived_at timestamptz,
  deleted_at timestamptz,
  sync_head bigint not null default 0 check (sync_head >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (id, workspace_type),
  check ((lifecycle_state = 'active' and archived_at is null and deleted_at is null)
      or (lifecycle_state = 'archived' and archived_at is not null and deleted_at is null)
      or (lifecycle_state = 'deleted' and deleted_at is not null))
);

create table public.expense_profiles (
  workspace_id uuid primary key,
  workspace_type text not null default 'expense' check (workspace_type = 'expense'),
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (workspace_id, workspace_type) references public.workspaces(id, workspace_type)
);

create table public.ledger_profiles (
  workspace_id uuid primary key,
  workspace_type text not null default 'ledger' check (workspace_type = 'ledger'),
  legal_name text not null check (btrim(legal_name) <> ''),
  tax_registration_no text,
  tax_region_code text,
  dealer_type text check (dealer_type in ('regular','composition','unregistered','consumer')),
  business_address text,
  business_email text,
  business_phone text,
  logo_object_key text,
  signature_object_key text,
  signatory_name text,
  bank_name text,
  bank_account_no text,
  bank_routing_code text,
  payment_address text,
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  foreign key (workspace_id, workspace_type) references public.workspaces(id, workspace_type)
);

create table public.workspace_memberships (
  workspace_id uuid not null references public.workspaces(id),
  user_id uuid not null references public.users(id),
  role text not null check (role in ('admin','accountant','editor','viewer')),
  state text not null default 'pending',
  activated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  primary key (workspace_id, user_id),
  check ((state = 'pending' and activated_at is null and revoked_at is null)
      or (state = 'active' and activated_at is not null and revoked_at is null)
      or (state = 'revoked' and revoked_at is not null
          and (activated_at is null or revoked_at >= activated_at)))
);

create table public.expense_wallets (
  id uuid primary key,
  workspace_id uuid not null references public.expense_profiles(workspace_id),
  name text not null check (btrim(name) <> ''),
  wallet_type text not null check (wallet_type in ('cash','bank','credit_card','digital_wallet','savings')),
  opening_balance_minor bigint not null default 0,
  icon_name text,
  color_hex text check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.expense_categories (
  id uuid primary key,
  workspace_id uuid not null references public.expense_profiles(workspace_id),
  name text not null check (btrim(name) <> ''),
  category_type text not null check (category_type in ('expense','income')),
  parent_category_id uuid check (parent_category_id <> id),
  system_key text,
  icon_name text,
  color_hex text check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  archived_at timestamptz,
  unique (workspace_id, system_key),
  unique (workspace_id, id, category_type),
  foreign key (workspace_id, parent_category_id, category_type)
    references public.expense_categories(workspace_id, id, category_type),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.expense_recurring_rules (
  id uuid primary key,
  workspace_id uuid not null references public.expense_profiles(workspace_id),
  name text,
  transaction_type text not null,
  wallet_id uuid not null,
  to_wallet_id uuid,
  category_id uuid,
  amount_minor bigint not null,
  note text,
  interval_unit text not null check (interval_unit in ('day','week','month','year')),
  interval_count integer not null check (interval_count > 0),
  anchor_on date not null,
  next_occurrence_on date not null check (next_occurrence_on >= anchor_on),
  ends_on date check (ends_on >= anchor_on),
  is_active boolean not null default true,
  check (transaction_type in ('expense','income','transfer')),
  check (amount_minor > 0),
  check ((transaction_type = 'transfer' and to_wallet_id is not null and to_wallet_id <> wallet_id and category_id is null)
      or (transaction_type <> 'transfer' and to_wallet_id is null)),
  foreign key (workspace_id, wallet_id) references public.expense_wallets(workspace_id, id),
  foreign key (workspace_id, to_wallet_id) references public.expense_wallets(workspace_id, id),
  foreign key (workspace_id, category_id) references public.expense_categories(workspace_id, id),
  foreign key (workspace_id, category_id, transaction_type)
    references public.expense_categories(workspace_id, id, category_type),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.expense_transactions (
  id uuid primary key,
  workspace_id uuid not null references public.expense_profiles(workspace_id),
  transaction_type text not null,
  wallet_id uuid not null,
  to_wallet_id uuid,
  category_id uuid,
  amount_minor bigint not null,
  occurred_at timestamptz not null,
  note text,
  reference_number text,
  receipt_object_key text,
  recurring_rule_id uuid,
  occurrence_on date,
  check ((recurring_rule_id is null) = (occurrence_on is null)),
  unique (workspace_id, recurring_rule_id, occurrence_on),
  check (transaction_type in ('expense','income','transfer')),
  check (amount_minor > 0),
  check ((transaction_type = 'transfer' and to_wallet_id is not null and to_wallet_id <> wallet_id and category_id is null)
      or (transaction_type <> 'transfer' and to_wallet_id is null)),
  foreign key (workspace_id, wallet_id) references public.expense_wallets(workspace_id, id),
  foreign key (workspace_id, to_wallet_id) references public.expense_wallets(workspace_id, id),
  foreign key (workspace_id, category_id) references public.expense_categories(workspace_id, id),
  foreign key (workspace_id, category_id, transaction_type)
    references public.expense_categories(workspace_id, id, category_type),
  foreign key (workspace_id, recurring_rule_id) references public.expense_recurring_rules(workspace_id, id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.expense_budgets (
  id uuid primary key,
  workspace_id uuid not null references public.expense_profiles(workspace_id),
  category_id uuid,
  period_type text not null check (period_type in ('monthly','quarterly','yearly')),
  amount_minor bigint not null check (amount_minor >= 0),
  start_on date not null,
  rollover_enabled boolean not null default false,
  is_active boolean not null default true,
  foreign key (workspace_id, category_id) references public.expense_categories(workspace_id, id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.ledger_parties (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  name text not null check (btrim(name) <> ''),
  party_type text not null check (party_type in ('customer','supplier')),
  phone text,
  tax_registration_no text,
  tax_region_code text,
  address text,
  dealer_type text check (dealer_type in ('regular','composition','unregistered','consumer')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.ledger_accounts (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  account_type text not null check (account_type in ('asset','liability','equity','income','expense')),
  system_key text,
  parent_account_id uuid check (parent_account_id <> id),
  description text,
  archived_at timestamptz,
  unique (workspace_id, code),
  unique (workspace_id, system_key),
  check (system_key is distinct from 'accounts_receivable' or account_type = 'asset'),
  check (system_key is distinct from 'accounts_payable' or account_type = 'liability'),
  foreign key (workspace_id, parent_account_id) references public.ledger_accounts(workspace_id, id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.ledger_inventory_items (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  sku text not null check (btrim(sku) <> ''),
  name text not null check (btrim(name) <> ''),
  description text,
  unit text not null check (btrim(unit) <> ''),
  purchase_price_minor bigint not null default 0 check (purchase_price_minor >= 0),
  sale_price_minor bigint not null default 0 check (sale_price_minor >= 0),
  minimum_stock_qty numeric(20,6) not null default 0 check (minimum_stock_qty >= 0 and minimum_stock_qty <> 'NaN'),
  tax_item_code text,
  tax_rate_pct numeric(9,6) not null default 0 check (tax_rate_pct between 0 and 100),
  archived_at timestamptz,
  unique (workspace_id, sku),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.ledger_vouchers (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  document_type text not null check (document_type in
    ('sales','purchase','payment','receipt','contra','journal','sales_order','purchase_order','estimate')),
  document_number text check (btrim(document_number) <> ''),
  status text not null default 'draft' check (status in ('draft','issued','posted','converted','voided')),
  document_on date not null,
  due_on date check (due_on >= document_on),
  party_id uuid,
  party_name_snapshot text,
  source_voucher_id uuid check (source_voucher_id <> id),
  settlement_account_id uuid,
  destination_account_id uuid,
  classification_account_id uuid,
  payment_method text check (payment_method in ('cash','bank','upi','cheque','credit')),
  subtotal_minor bigint not null default 0 check (subtotal_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor between 0 and subtotal_minor),
  tax_minor bigint not null default 0 check (tax_minor >= 0),
  total_minor bigint not null default 0 check (total_minor = subtotal_minor - discount_minor + tax_minor),
  reference_number text,
  note text,
  receipt_object_key text,
  place_of_supply_code text,
  ship_to_address text,
  ship_to_tax_registration_no text,
  separate_ship_to boolean not null default false,
  tax_invoice_reference text,
  signed_qr text,
  waybill_number text,
  check (status = 'draft' or document_number is not null),
  check (status <> 'posted' or document_type not in ('sales_order','purchase_order','estimate')),
  check (status not in ('issued','converted') or document_type in ('sales_order','purchase_order','estimate')),
  unique (workspace_id, document_type, document_number),
  foreign key (workspace_id, party_id) references public.ledger_parties(workspace_id, id),
  foreign key (workspace_id, source_voucher_id) references public.ledger_vouchers(workspace_id, id),
  foreign key (workspace_id, settlement_account_id) references public.ledger_accounts(workspace_id, id),
  foreign key (workspace_id, destination_account_id) references public.ledger_accounts(workspace_id, id),
  foreign key (workspace_id, classification_account_id) references public.ledger_accounts(workspace_id, id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  deleted_at timestamptz,
  unique (workspace_id, id)
);
create table public.ledger_voucher_lines (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  voucher_id uuid not null,
  line_no integer not null check (line_no > 0),
  inventory_item_id uuid,
  description_snapshot text not null,
  sku_snapshot text,
  tax_item_code_snapshot text,
  unit_snapshot text not null,
  quantity numeric(20,6) not null check (quantity > 0 and quantity <> 'NaN'),
  unit_price_minor bigint not null check (unit_price_minor >= 0),
  discount_minor bigint not null default 0 check (discount_minor >= 0),
  tax_rate_pct numeric(9,6) not null default 0 check (tax_rate_pct between 0 and 100),
  central_tax_minor bigint not null default 0 check (central_tax_minor >= 0),
  state_tax_minor bigint not null default 0 check (state_tax_minor >= 0),
  integrated_tax_minor bigint not null default 0 check (integrated_tax_minor >= 0),
  line_total_minor bigint not null check (line_total_minor >= 0),
  unique (workspace_id, voucher_id, line_no),
  foreign key (workspace_id, voucher_id) references public.ledger_vouchers(workspace_id, id),
  foreign key (workspace_id, inventory_item_id) references public.ledger_inventory_items(workspace_id, id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  unique (workspace_id, id)
);
create table public.ledger_journals (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  source_kind text not null check (source_kind in ('voucher','party_activity','opening','manual','reversal')),
  voucher_id uuid,
  reverses_journal_id uuid check (reverses_journal_id <> id),
  effective_on date not null,
  posted_at timestamptz not null default now(),
  posted_by_user_id uuid references public.users(id),
  narration text,
  party_activity_kind text check (party_activity_kind in ('credit','payment')),
  payment_method text check (payment_method in ('cash','bank','upi','cheque')),
  receipt_object_key text,
  created_at timestamptz not null default now(),
  check ((source_kind = 'voucher') = (voucher_id is not null)),
  check ((source_kind = 'reversal') = (reverses_journal_id is not null)),
  check ((source_kind = 'party_activity') = (party_activity_kind is not null)),
  check (source_kind = 'party_activity' or (payment_method is null and receipt_object_key is null)),
  unique (workspace_id, voucher_id),
  unique (workspace_id, reverses_journal_id),
  foreign key (workspace_id, voucher_id) references public.ledger_vouchers(workspace_id, id),
  foreign key (workspace_id, reverses_journal_id) references public.ledger_journals(workspace_id, id),
  unique (workspace_id, id)
);
create table public.ledger_journal_lines (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  journal_id uuid not null,
  line_no integer not null check (line_no > 0),
  account_id uuid not null,
  party_id uuid,
  debit_minor bigint not null default 0,
  credit_minor bigint not null default 0,
  narration text,
  created_at timestamptz not null default now(),
  check ((debit_minor > 0 and credit_minor = 0) or (credit_minor > 0 and debit_minor = 0)),
  unique (workspace_id, journal_id, line_no),
  foreign key (workspace_id, journal_id) references public.ledger_journals(workspace_id, id),
  foreign key (workspace_id, account_id) references public.ledger_accounts(workspace_id, id),
  foreign key (workspace_id, party_id) references public.ledger_parties(workspace_id, id),
  unique (workspace_id, id)
);
create table public.ledger_stock_movements (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  inventory_item_id uuid not null,
  journal_id uuid,
  voucher_line_id uuid,
  reverses_movement_id uuid check (reverses_movement_id <> id),
  movement_kind text not null check (movement_kind in ('opening','receipt','issue','adjustment','wastage','reversal')),
  quantity_delta numeric(20,6) not null check (quantity_delta <> 0 and quantity_delta <> 'NaN'),
  unit_cost_minor bigint check (unit_cost_minor >= 0),
  extended_cost_minor bigint check (extended_cost_minor >= 0),
  effective_on date not null,
  note text,
  created_at timestamptz not null default now(),
  check ((movement_kind = 'reversal') = (reverses_movement_id is not null)),
  check (movement_kind not in ('opening','receipt') or quantity_delta > 0),
  check (movement_kind not in ('issue','wastage') or quantity_delta < 0),
  check (voucher_line_id is null or journal_id is not null),
  unique (workspace_id, reverses_movement_id),
  foreign key (workspace_id, inventory_item_id) references public.ledger_inventory_items(workspace_id, id),
  foreign key (workspace_id, journal_id) references public.ledger_journals(workspace_id, id),
  foreign key (workspace_id, voucher_line_id) references public.ledger_voucher_lines(workspace_id, id),
  foreign key (workspace_id, reverses_movement_id) references public.ledger_stock_movements(workspace_id, id),
  unique (workspace_id, id)
);
create table public.ledger_audit_events (
  id uuid primary key,
  workspace_id uuid not null references public.ledger_profiles(workspace_id),
  actor_user_id uuid references public.users(id),
  actor_kind text not null check (actor_kind in ('user','system')),
  operation_id uuid not null,
  action text not null check (action in ('post','reverse','stock_movement','draft','issue','workspace','master','document')),
  subject_type text not null check (subject_type in
    ('workspace','ledger_profiles','ledger_journals','ledger_vouchers','ledger_parties','ledger_accounts','ledger_inventory_items','ledger_stock_movements')),
  subject_id uuid not null,
  occurred_at timestamptz not null default now(),
  detail_version integer not null default 1 check (detail_version > 0),
  details jsonb check (jsonb_typeof(details) = 'object'),
  check ((actor_kind = 'user') = (actor_user_id is not null)),
  unique (workspace_id, id)
);

create table private.workspace_commits (
  workspace_id uuid not null references public.workspaces(id),
  sequence bigint not null check (sequence > 0),
  operation_id uuid not null,
  actor_user_id uuid references public.users(id),
  command_kind text not null,
  protocol_version integer not null default 1 check (protocol_version > 0),
  request_hash bytea not null check (octet_length(request_hash) = 32),
  committed_at timestamptz not null default now(),
  changes jsonb check (jsonb_typeof(changes) = 'array'),
  primary key (workspace_id, sequence),
  unique (workspace_id, operation_id)
);

create unique index expense_budgets_live_key
  on public.expense_budgets (workspace_id, category_id, period_type, start_on) nulls not distinct
  where deleted_at is null;
create index workspaces_owner_lookup on public.workspaces (owner_user_id, lifecycle_state, updated_at, id);
create index memberships_by_user on public.workspace_memberships (user_id, state, workspace_id);
create index expense_timeline on public.expense_transactions (workspace_id, occurred_at, id) where deleted_at is null;
create index expense_by_wallet on public.expense_transactions (workspace_id, wallet_id, occurred_at);
create index expense_by_destination on public.expense_transactions (workspace_id, to_wallet_id, occurred_at);
create index expense_by_category on public.expense_transactions (workspace_id, category_id, occurred_at);
create index expense_rules_due on public.expense_recurring_rules (workspace_id, next_occurrence_on, id)
  where deleted_at is null and is_active;
create index expense_budget_period on public.expense_budgets (workspace_id, period_type, start_on) where deleted_at is null and is_active;
create index ledger_party_list on public.ledger_parties (workspace_id, name, id);
create index ledger_voucher_timeline on public.ledger_vouchers (workspace_id, status, document_on, id);
create index ledger_voucher_party on public.ledger_vouchers (workspace_id, party_id, document_on);
create index ledger_journal_timeline on public.ledger_journals (workspace_id, effective_on, id);
create index ledger_lines_by_account on public.ledger_journal_lines (workspace_id, account_id, journal_id);
create index ledger_lines_by_party on public.ledger_journal_lines (workspace_id, party_id, journal_id);
create index ledger_stock_history on public.ledger_stock_movements (workspace_id, inventory_item_id, effective_on, id);
create index ledger_audit_timeline on public.ledger_audit_events (workspace_id, occurred_at, id);
create index ledger_audit_subject on public.ledger_audit_events (workspace_id, subject_type, subject_id);

create index on public.expense_categories (workspace_id, parent_category_id);
create index on public.expense_recurring_rules (workspace_id, wallet_id);
create index on public.expense_recurring_rules (workspace_id, to_wallet_id);
create index on public.expense_recurring_rules (workspace_id, category_id);
create index on public.expense_budgets (workspace_id, category_id);
create index on public.ledger_accounts (workspace_id, parent_account_id);
create index on public.ledger_vouchers (workspace_id, source_voucher_id);
create index on public.ledger_vouchers (workspace_id, settlement_account_id);
create index on public.ledger_vouchers (workspace_id, destination_account_id);
create index on public.ledger_vouchers (workspace_id, classification_account_id);
create index on public.ledger_voucher_lines (workspace_id, inventory_item_id);
create index on public.ledger_stock_movements (workspace_id, journal_id);
create index on public.ledger_stock_movements (workspace_id, voucher_line_id);
create index on public.ledger_audit_events (actor_user_id);
create index on public.ledger_journals (posted_by_user_id);
create index on private.workspace_commits (actor_user_id);

commit;
