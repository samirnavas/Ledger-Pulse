begin;

create function ledgerpulse_internal.assert_subtype() returns trigger
language plpgsql security definer set search_path = pg_catalog as $$
declare
  workspace uuid := case when tg_table_name = 'workspaces'
    then coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id')::uuid
    else coalesce(to_jsonb(new)->>'workspace_id', to_jsonb(old)->>'workspace_id')::uuid end;
  kind text;
begin
  select workspace_type into kind from public.workspaces where id = workspace;
  if found and (
    (kind = 'expense' and not exists (select 1 from public.expense_profiles where workspace_id = workspace))
    or (kind = 'ledger' and not exists (select 1 from public.ledger_profiles where workspace_id = workspace))
  ) then
    raise exception 'workspace requires its matching subtype' using errcode = '23514';
  end if;
  return null;
end $$;


create function ledgerpulse_internal.require_live_reference(p_table text, p_workspace uuid, p_id uuid)
returns void language plpgsql set search_path = pg_catalog as $$
declare eligible boolean;
begin
  if p_id is null then return; end if;
  execute format('select exists (select 1 from public.%I
    where workspace_id = $1 and id = $2 and archived_at is null and deleted_at is null)',p_table)
    into eligible using p_workspace,p_id;
  if not eligible then raise exception 'reference must be active in the workspace' using errcode = '23503'; end if;
end $$;

create function ledgerpulse_internal.validate_tree(p_table text, p_workspace uuid,
  p_id uuid, p_parent uuid, p_column text)
returns void language plpgsql set search_path = pg_catalog as $$
declare cycle_found boolean;
begin
  if p_parent is null then return; end if;
  execute format('with recursive ancestors(id) as (
    select $1::uuid union
    select t.%1$I from public.%2$I t join ancestors a on a.id = t.id
    where t.workspace_id = $2 and t.%1$I is not null
  ) select exists (select 1 from ancestors where id = $3)', p_column,p_table)
  into cycle_found using p_parent,p_workspace,p_id;
  if cycle_found then raise exception 'parent hierarchy cycle' using errcode = '23514'; end if;
end $$;

-- Fixed relation and writable column allowlists. All dynamic identifiers below
-- originate in the contract or have been checked against that contract.
create function ledgerpulse_internal.write_entity(p_workspace uuid, p_table text,
  p_id uuid, p_revision bigint, p_data jsonb) returns jsonb
language plpgsql set search_path = pg_catalog as $$
declare
  allowed text[];
  key_column text := 'id';
  previous jsonb;
  merged jsonb;
  key_name text;
  columns text := '';
  values_sql text := '';
  assignments text := '';
  saved jsonb;
  parent_voucher public.ledger_vouchers%rowtype;
begin
  allowed := case p_table
    when 'expense_profiles' then array['time_zone']
    when 'ledger_profiles' then array['time_zone','legal_name','tax_registration_no','tax_region_code','dealer_type',
      'business_address','business_email','business_phone','signatory_name','bank_name','bank_account_no',
      'bank_routing_code','payment_address','logo_object_key','signature_object_key']
    when 'expense_wallets' then array['name','wallet_type','opening_balance_minor','icon_name','color_hex','archived_at','deleted_at']
    when 'expense_categories' then array['name','category_type','parent_category_id','system_key','icon_name','color_hex','archived_at','deleted_at']
    when 'expense_transactions' then array['transaction_type','wallet_id','to_wallet_id','category_id','amount_minor',
      'occurred_at','note','reference_number','receipt_object_key','deleted_at']
    when 'expense_budgets' then array['category_id','period_type','amount_minor','start_on','rollover_enabled','is_active','deleted_at']
    when 'expense_recurring_rules' then array['name','transaction_type','wallet_id','to_wallet_id','category_id',
      'amount_minor','note','interval_unit','interval_count','anchor_on','next_occurrence_on','ends_on','is_active','deleted_at']
    when 'ledger_parties' then array['name','party_type','phone','tax_registration_no','tax_region_code','address',
      'dealer_type','archived_at','deleted_at']
    when 'ledger_accounts' then array['code','name','account_type','system_key','parent_account_id','description','archived_at','deleted_at']
    when 'ledger_inventory_items' then array['sku','name','description','unit','purchase_price_minor','sale_price_minor',
      'minimum_stock_qty','tax_item_code','tax_rate_pct','archived_at','deleted_at']
    when 'ledger_vouchers' then array['document_type','document_on','due_on','party_id','source_voucher_id',
      'settlement_account_id','destination_account_id','classification_account_id','payment_method',
      'subtotal_minor','discount_minor','tax_minor','total_minor','reference_number','note',
      'place_of_supply_code','ship_to_address','ship_to_tax_registration_no','separate_ship_to','receipt_object_key','deleted_at']
    when 'ledger_voucher_lines' then array['voucher_id','line_no','inventory_item_id','description_snapshot',
      'sku_snapshot','tax_item_code_snapshot','unit_snapshot','quantity','unit_price_minor','discount_minor',
      'tax_rate_pct','central_tax_minor','state_tax_minor','integrated_tax_minor','line_total_minor']
    else null end;
  if allowed is null or p_id is null or p_revision is null or p_revision < 0
      or jsonb_typeof(p_data) is distinct from 'object'
      or exists (select 1 from jsonb_object_keys(p_data) k where k <> all(allowed)) then
    raise exception 'invalid entity mutation' using errcode = '22023';
  end if;
  if p_table in ('expense_profiles','ledger_profiles') then
    if p_id <> p_workspace or p_revision = 0 then
      raise exception 'invalid subtype mutation' using errcode = '22023';
    end if;
    key_column := 'workspace_id';
  end if;
  execute format('select to_jsonb(t) from public.%I t where workspace_id = $1 and %I = $2',p_table,key_column)
    into previous using p_workspace,p_id;
  if coalesce((previous->>'revision')::bigint,0) <> p_revision then
    raise exception 'entity revision conflict' using errcode = '40001',
      detail = jsonb_build_object('current_revision', previous->>'revision')::text;
  end if;
  -- A boolean request does not control the stored deletion time.
  if p_data ? 'deleted_at' and p_data->'deleted_at' <> 'null'::jsonb then
    if p_data->'deleted_at' <> 'true'::jsonb or previous is null then
      raise exception 'invalid deletion request' using errcode = '22023';
    end if;
    p_data := jsonb_set(p_data,'{deleted_at}',to_jsonb(clock_timestamp()));
  end if;
  merged := coalesce(previous,'{}'::jsonb) || p_data;
  foreach key_name in array array['receipt_object_key','logo_object_key','signature_object_key'] loop
    if p_data ? key_name then
      perform ledgerpulse_internal.require_object('workspaces/' || p_workspace,p_data->>key_name);
    end if;
  end loop;
  if p_data ? 'time_zone' and not exists (select 1 from pg_timezone_names where name = p_data->>'time_zone') then
    raise exception 'unknown time zone' using errcode = '22023';
  end if;
  if p_table in ('expense_transactions','expense_recurring_rules')
      and (previous is null or p_data ?| array['wallet_id','to_wallet_id','category_id']
        or (previous->>'deleted_at' is not null and merged->>'deleted_at' is null)) then
    perform ledgerpulse_internal.require_live_reference('expense_wallets',p_workspace,(merged->>'wallet_id')::uuid);
    perform ledgerpulse_internal.require_live_reference('expense_wallets',p_workspace,(merged->>'to_wallet_id')::uuid);
    perform ledgerpulse_internal.require_live_reference('expense_categories',p_workspace,(merged->>'category_id')::uuid);
  elsif p_table = 'expense_budgets' and (previous is null or p_data ? 'category_id'
      or (previous->>'deleted_at' is not null and merged->>'deleted_at' is null)) then
    perform ledgerpulse_internal.require_live_reference('expense_categories',p_workspace,(merged->>'category_id')::uuid);
  elsif p_table = 'expense_categories' and p_data ? 'parent_category_id' then
    perform ledgerpulse_internal.require_live_reference('expense_categories',p_workspace,(merged->>'parent_category_id')::uuid);
    perform ledgerpulse_internal.validate_tree(p_table,p_workspace,p_id,(merged->>'parent_category_id')::uuid,'parent_category_id');
  elsif p_table = 'ledger_accounts' then
    if p_data ? 'parent_account_id' then
      perform ledgerpulse_internal.require_live_reference('ledger_accounts',p_workspace,(merged->>'parent_account_id')::uuid);
      perform ledgerpulse_internal.validate_tree(p_table,p_workspace,p_id,(merged->>'parent_account_id')::uuid,'parent_account_id');
    end if;
    if exists (select 1 from public.ledger_journal_lines where workspace_id = p_workspace and account_id = p_id)
      and (merged->>'account_type',merged->>'system_key')
        is distinct from (previous->>'account_type',previous->>'system_key') then
      raise exception 'posted account classifications are immutable' using errcode = '23514';
    end if;
  elsif p_table = 'ledger_parties' and p_data ? 'party_type'
      and merged->>'party_type' is distinct from previous->>'party_type'
      and exists (select 1 from public.ledger_journal_lines where workspace_id = p_workspace and party_id = p_id) then
    raise exception 'posted party classification is immutable' using errcode = '23514';
  elsif p_table = 'expense_wallets' and p_data ? 'opening_balance_minor'
      and merged->>'opening_balance_minor' is distinct from previous->>'opening_balance_minor'
      and exists (select 1 from public.expense_transactions where workspace_id = p_workspace
        and (wallet_id = p_id or to_wallet_id = p_id)) then
    raise exception 'wallet has movements' using errcode = '23514';
  elsif p_table = 'ledger_vouchers' then
    if previous is not null and previous->>'status' <> 'draft' then
      raise exception 'issued document is immutable' using errcode = '23514';
    end if;
    perform ledgerpulse_internal.require_live_reference('ledger_parties',p_workspace,(merged->>'party_id')::uuid);
    foreach key_name in array array['settlement_account_id','destination_account_id','classification_account_id'] loop
      perform ledgerpulse_internal.require_live_reference('ledger_accounts',p_workspace,(merged->>key_name)::uuid);
    end loop;
    if p_data ? 'source_voucher_id' then
      perform ledgerpulse_internal.validate_tree(p_table,p_workspace,p_id,(merged->>'source_voucher_id')::uuid,'source_voucher_id');
    end if;
  elsif p_table = 'ledger_voucher_lines' then
    if previous is not null and merged->>'voucher_id' is distinct from previous->>'voucher_id' then
      raise exception 'voucher line cannot be moved' using errcode = '23514';
    end if;
    select * into parent_voucher from public.ledger_vouchers
      where workspace_id = p_workspace and id = (merged->>'voucher_id')::uuid;
    if not found or parent_voucher.status <> 'draft' or parent_voucher.deleted_at is not null then
      raise exception 'editable voucher not found' using errcode = '23503';
    end if;
    perform ledgerpulse_internal.require_live_reference('ledger_inventory_items',p_workspace,(merged->>'inventory_item_id')::uuid);
  end if;

  for key_name in select jsonb_object_keys(p_data) order by 1 loop
    columns := columns || format(', %I', key_name);
    values_sql := values_sql || format(', r.%I', key_name);
    assignments := assignments || format(', %1$I = r.%1$I', key_name);
  end loop;

  if previous is null then
    execute format('insert into public.%1$I as t (id, workspace_id%2$s)
      select $2, $1%3$s from jsonb_populate_record(null::public.%1$I,$3) r returning to_jsonb(t)',
      p_table,columns,values_sql) into saved using p_workspace,p_id,p_data;
  else
    execute format('update public.%1$I t set revision = t.revision + 1, updated_at = clock_timestamp()%2$s
      from jsonb_populate_record(null::public.%1$I,$3) r
      where t.workspace_id = $1 and t.%3$I = $2 returning to_jsonb(t)',
      p_table,assignments,key_column) into saved using p_workspace,p_id,p_data;
  end if;

  if p_table = 'ledger_voucher_lines' then
    update public.ledger_vouchers set revision = revision + 1, updated_at = clock_timestamp()
      where workspace_id = p_workspace and id = parent_voucher.id;
  end if;
  return saved;
end $$;

create function ledgerpulse_internal.audit(p_workspace uuid,p_actor uuid,p_operation uuid,
  p_action text,p_subject text,p_id uuid) returns void
language sql set search_path = pg_catalog as $$
  insert into public.ledger_audit_events
    (id,workspace_id,actor_user_id,actor_kind,operation_id,action,subject_type,subject_id)
  values (gen_random_uuid(),p_workspace,p_actor,'user',p_operation,p_action,p_subject,p_id)
$$;

create function ledgerpulse_internal.post_journal(p_workspace uuid,p_actor uuid,p_data jsonb)
returns uuid language plpgsql set search_path = pg_catalog as $$
declare
  posting uuid := (p_data->>'id')::uuid;
  kind text := p_data->>'source_kind';
  voucher public.ledger_vouchers%rowtype;
  line jsonb;
  account uuid;
  party uuid;
  debit bigint;
  credit bigint;
  line_count integer := 0;
  control_count integer := 0;
  total_debit numeric := 0;
  total_credit numeric := 0;
  control_effect numeric := 0;
  expected_control numeric;
  system_code text;
  number_value bigint;
  document_line public.ledger_voucher_lines%rowtype;
  source_document public.ledger_vouchers%rowtype;
  line_total numeric;
  line_tax numeric;
  document_line_count bigint;
  current_party_type text;
begin
  if posting is null or kind is null or kind not in ('voucher','manual','opening','party_activity')
    or jsonb_typeof(p_data->'lines') is distinct from 'array'
    or jsonb_array_length(p_data->'lines') not between 2 and 500 then
    raise exception 'invalid journal request' using errcode = '22023';
  end if;
  if kind = 'voucher' then
    select * into voucher from public.ledger_vouchers
      where workspace_id = p_workspace and id = (p_data->>'voucher_id')::uuid;
    if not found or voucher.deleted_at is not null or voucher.status <> 'draft' then
      raise exception 'postable voucher not found' using errcode = '23514';
    end if;
    if voucher.revision is distinct from (p_data->>'expected_revision')::bigint then
      raise exception 'voucher revision conflict' using errcode = '40001';
    end if;
    if voucher.document_type in ('sales_order','purchase_order','estimate') or voucher.total_minor <= 0 then
      raise exception 'voucher cannot be posted' using errcode = '23514';
    end if;
    perform ledgerpulse_internal.require_live_reference('ledger_parties',p_workspace,voucher.party_id);
    perform ledgerpulse_internal.require_live_reference('ledger_accounts',p_workspace,voucher.settlement_account_id);
    perform ledgerpulse_internal.require_live_reference('ledger_accounts',p_workspace,voucher.destination_account_id);
    perform ledgerpulse_internal.require_live_reference('ledger_accounts',p_workspace,voucher.classification_account_id);
    if voucher.source_voucher_id is not null then
      select * into strict source_document from public.ledger_vouchers
        where workspace_id = p_workspace and id = voucher.source_voucher_id;
      if source_document.status <> 'issued' or source_document.deleted_at is not null
        or not ((voucher.document_type = 'sales' and source_document.document_type in ('sales_order','estimate'))
          or (voucher.document_type = 'purchase' and source_document.document_type = 'purchase_order')) then
        raise exception 'ineligible conversion source' using errcode = '23514';
      end if;
    end if;
    select count(*), sum(line_total_minor), sum(central_tax_minor::numeric + state_tax_minor + integrated_tax_minor)
      into document_line_count,line_total,line_tax from public.ledger_voucher_lines
      where workspace_id = p_workspace and voucher_id = voucher.id;
    if document_line_count > 500
      or (line_total is not null and (line_total <> voucher.total_minor or line_tax <> voucher.tax_minor))
      or (line_total is null and voucher.tax_minor <> 0) then
      raise exception 'voucher lines do not reconcile to document totals' using errcode = '23514';
    end if;
  elsif p_data ? 'voucher_id' then
    raise exception 'voucher association requires voucher posting' using errcode = '22023';
  end if;

  perform ledgerpulse_internal.require_object('workspaces/' || p_workspace,p_data->>'receipt_object_key');
  insert into public.ledger_journals (id,workspace_id,source_kind,voucher_id,effective_on,
    posted_by_user_id,narration,party_activity_kind,payment_method,receipt_object_key)
  values (posting,p_workspace,kind,voucher.id,
    case when kind = 'voucher' then voucher.document_on else (p_data->>'effective_on')::date end,
    p_actor,p_data->>'narration',p_data->>'party_activity_kind',p_data->>'payment_method',p_data->>'receipt_object_key');

  for line in select value from jsonb_array_elements(p_data->'lines') loop
    line_count := line_count + 1;
    account := (line->>'account_id')::uuid;
    party := (line->>'party_id')::uuid;
    debit := coalesce((line->>'debit_minor')::bigint,0);
    credit := coalesce((line->>'credit_minor')::bigint,0);
    perform ledgerpulse_internal.require_live_reference('ledger_accounts',p_workspace,account);
    perform ledgerpulse_internal.require_live_reference('ledger_parties',p_workspace,party);
    select system_key into system_code from public.ledger_accounts
      where workspace_id = p_workspace and id = account;
    if (system_code is not distinct from 'accounts_receivable' or system_code is not distinct from 'accounts_payable')
      <> (party is not null) then
      raise exception 'party dimension belongs only on a control account' using errcode = '23514';
    end if;
    if party is not null then
      select party_type into current_party_type from public.ledger_parties
        where workspace_id = p_workspace and id = party;
      if (system_code = 'accounts_receivable' and current_party_type <> 'customer')
        or (system_code = 'accounts_payable' and current_party_type <> 'supplier') then
        raise exception 'party type does not match the control account' using errcode = '23514';
      end if;
      control_count := control_count + 1;
      control_effect := control_effect + debit - credit;
      if kind = 'voucher' and party is distinct from voucher.party_id then
        raise exception 'posting counterparty does not match voucher' using errcode = '23514';
      end if;
    end if;
    insert into public.ledger_journal_lines (id,workspace_id,journal_id,line_no,account_id,party_id,
      debit_minor,credit_minor,narration)
    values ((line->>'id')::uuid,p_workspace,posting,line_count,account,party,debit,credit,line->>'narration');
    total_debit := total_debit + debit;
    total_credit := total_credit + credit;
  end loop;
  if total_debit <> total_credit or (kind = 'party_activity' and control_count <> 1)
    or (kind = 'voucher' and total_debit <> voucher.total_minor) then
    raise exception 'posting does not balance against its source' using errcode = '23514';
  end if;
  if kind = 'voucher' and voucher.party_id is not null then
    expected_control := case voucher.document_type
      when 'sales' then voucher.total_minor when 'receipt' then -voucher.total_minor
      when 'purchase' then -voucher.total_minor when 'payment' then voucher.total_minor else null end;
    if expected_control is not null and control_effect <> expected_control
      and not (voucher.document_type in ('sales','purchase')
        and coalesce(voucher.payment_method in ('cash','bank','upi','cheque'),false) and control_count = 0) then
      raise exception 'voucher control effect does not match document' using errcode = '23514';
    end if;
  end if;

  if kind = 'voucher' then
    for document_line in select * from public.ledger_voucher_lines
      where workspace_id = p_workspace and voucher_id = voucher.id and inventory_item_id is not null
      order by line_no loop
      if voucher.document_type not in ('sales','purchase') then
        raise exception 'stock lines require sales or purchase posting' using errcode = '23514';
      end if;
      perform ledgerpulse_internal.require_live_reference('ledger_inventory_items',p_workspace,document_line.inventory_item_id);
      insert into public.ledger_stock_movements
        (id,workspace_id,inventory_item_id,journal_id,voucher_line_id,movement_kind,quantity_delta,effective_on)
      values (gen_random_uuid(),p_workspace,document_line.inventory_item_id,posting,document_line.id,
        case when voucher.document_type = 'sales' then 'issue' else 'receipt' end,
        case when voucher.document_type = 'sales' then -document_line.quantity else document_line.quantity end,
        voucher.document_on);
    end loop;
    select count(*)+1 into number_value from public.ledger_vouchers
      where workspace_id = p_workspace and document_type = voucher.document_type and document_number is not null;
    update public.ledger_vouchers set status = 'posted', document_number = upper(document_type)||'-'||number_value,
      revision = revision + 1, updated_at = clock_timestamp(),
      party_name_snapshot = (select name from public.ledger_parties where workspace_id = p_workspace and id = voucher.party_id)
      where workspace_id = p_workspace and id = voucher.id;
    if voucher.source_voucher_id is not null then
      update public.ledger_vouchers set status = 'converted', revision = revision + 1, updated_at = clock_timestamp()
        where workspace_id = p_workspace and id = voucher.source_voucher_id;
    end if;
  end if;
  return posting;
end $$;

create function ledgerpulse_internal.reverse_journal(p_workspace uuid,p_actor uuid,p_data jsonb)
returns uuid language plpgsql set search_path = pg_catalog as $$
declare
  reversal uuid := (p_data->>'id')::uuid;
  effective_date date := (p_data->>'effective_on')::date;
  original public.ledger_journals%rowtype;
begin
  select * into original from public.ledger_journals
    where workspace_id = p_workspace and id = (p_data->>'journal_id')::uuid;
  if not found or original.source_kind = 'reversal' or effective_date < original.effective_on then
    raise exception 'original journal unavailable or reversal date invalid' using errcode = '23514';
  end if;
  insert into public.ledger_journals
    (id,workspace_id,source_kind,reverses_journal_id,effective_on,posted_by_user_id,narration)
  values (reversal,p_workspace,'reversal',original.id,effective_date,p_actor,p_data->>'narration');
  insert into public.ledger_journal_lines
    (id,workspace_id,journal_id,line_no,account_id,party_id,debit_minor,credit_minor,narration)
  select gen_random_uuid(),p_workspace,reversal,line_no,account_id,party_id,credit_minor,debit_minor,narration
    from public.ledger_journal_lines where workspace_id = p_workspace and journal_id = original.id order by line_no;
  insert into public.ledger_stock_movements
    (id,workspace_id,inventory_item_id,journal_id,reverses_movement_id,movement_kind,
     quantity_delta,unit_cost_minor,extended_cost_minor,effective_on)
  select gen_random_uuid(),p_workspace,inventory_item_id,reversal,id,'reversal',
    -quantity_delta,unit_cost_minor,extended_cost_minor,effective_date
    from public.ledger_stock_movements where workspace_id = p_workspace and journal_id = original.id order by id;
  if original.voucher_id is not null then
    update public.ledger_vouchers set status = 'voided',revision = revision + 1,updated_at = clock_timestamp()
      where workspace_id = p_workspace and id = original.voucher_id;
  end if;
  return reversal;
end $$;

create constraint trigger workspace_subtype after insert or update on public.workspaces
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_subtype();
create constraint trigger expense_subtype after insert or update or delete on public.expense_profiles
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_subtype();
create constraint trigger ledger_subtype after insert or update or delete on public.ledger_profiles
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_subtype();

create function ledgerpulse_internal.protect_identity() returns trigger
language plpgsql set search_path = pg_catalog as $$
begin
  if tg_table_name = 'workspaces' then
    if (new.id, new.owner_user_id, new.workspace_type)
      is distinct from (old.id, old.owner_user_id, old.workspace_type) then
      raise exception 'workspace identity, owner and type are immutable' using errcode = '23514';
    end if;
    if new.currency_code <> old.currency_code and (
      exists (select 1 from public.expense_wallets where workspace_id = old.id)
      or exists (select 1 from public.expense_budgets where workspace_id = old.id)
      or exists (select 1 from public.ledger_vouchers where workspace_id = old.id)
      or exists (select 1 from public.ledger_journals where workspace_id = old.id)
      or exists (select 1 from public.ledger_inventory_items where workspace_id = old.id)
    ) then
      raise exception 'workspace currency is locked by financial data' using errcode = '23514';
    end if;
  elsif (new.workspace_id, new.workspace_type) is distinct from (old.workspace_id, old.workspace_type) then
    raise exception 'subtype identity is immutable' using errcode = '23514';
  end if;
  return new;
end $$;

create trigger workspace_identity before update on public.workspaces
  for each row execute function ledgerpulse_internal.protect_identity();
create trigger expense_identity before update on public.expense_profiles
  for each row execute function ledgerpulse_internal.protect_identity();
create trigger ledger_identity before update on public.ledger_profiles
  for each row execute function ledgerpulse_internal.protect_identity();

create function ledgerpulse_internal.seed_user() returns trigger
language plpgsql security definer set search_path = pg_catalog as $$
begin
  insert into public.users (id, display_name)
  values (new.id, coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data->>'name'), ''), 'User'))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger ledgerpulse_auth_user_created after insert on auth.users
  for each row execute function ledgerpulse_internal.seed_user();

insert into public.users (id, display_name)
select id, coalesce(nullif(btrim(raw_user_meta_data->>'full_name'), ''),
  nullif(btrim(raw_user_meta_data->>'name'), ''), 'User')
from auth.users on conflict (id) do nothing;

create function public.ledgerpulse_initialize_user() returns uuid
language plpgsql security definer set search_path = pg_catalog as $$
declare actor uuid := auth.uid();
begin
  if actor is null or not exists (select 1 from auth.users where id = actor) then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  insert into public.users (id, display_name) values (actor, 'User') on conflict (id) do nothing;
  return actor;
end $$;

insert into storage.buckets (id, name, public)
values ('ledgerpulse-private','ledgerpulse-private',false);

-- Object keys are immutable. Clients upload a new object before replacing the
-- reference. A separate privileged retention job may reclaim unreferenced files.
create policy ledgerpulse_object_read on storage.objects
for select to authenticated using (
  bucket_id = 'ledgerpulse-private'
  and name ~ '^(users|workspaces)/[0-9a-f-]{36}/[0-9a-f-]{36}$'
  and (
    (split_part(name,'/',1) = 'users' and split_part(name,'/',2) = (select auth.uid())::text)
    or (split_part(name,'/',1) = 'workspaces' and exists (
      select 1 from public.workspaces w where w.id::text = split_part(objects.name,'/',2)
      and w.owner_user_id = (select auth.uid()) and w.lifecycle_state <> 'deleted'))
  )
);
create policy ledgerpulse_object_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'ledgerpulse-private'
  and name ~ '^(users|workspaces)/[0-9a-f-]{36}/[0-9a-f-]{36}$'
  and (
    (split_part(name,'/',1) = 'users' and split_part(name,'/',2) = (select auth.uid())::text)
    or (split_part(name,'/',1) = 'workspaces' and exists (
      select 1 from public.workspaces w where w.id::text = split_part(objects.name,'/',2)
      and w.owner_user_id = (select auth.uid()) and w.lifecycle_state = 'active'))
  )
);

create function ledgerpulse_internal.require_object(p_prefix text,p_key text) returns void
language plpgsql set search_path = pg_catalog as $$
begin
  if p_key is not null and (
    p_key !~ ('^' || p_prefix || '/[0-9a-f-]{36}$')
    or not exists (select 1 from storage.objects where bucket_id = 'ledgerpulse-private' and name = p_key)
  ) then
    raise exception 'object is unavailable in this scope' using errcode = '23503';
  end if;
end $$;

create function public.ledgerpulse_update_user(p_expected_revision bigint, p_display_name text,
  p_locale text, p_theme text, p_avatar_object_key text default null) returns text
language plpgsql security definer set search_path = pg_catalog as $$
declare
  profile public.users%rowtype;
  next_revision bigint;
begin
  select * into profile from public.users where id = auth.uid() for update;
  if not found then raise exception 'authentication required' using errcode = '42501'; end if;
  if (profile.display_name, profile.locale, profile.theme_preference, profile.avatar_object_key)
    is not distinct from (btrim(p_display_name), p_locale, p_theme, p_avatar_object_key) then
    return profile.revision::text;
  end if;
  if profile.revision is distinct from p_expected_revision then
    raise exception 'profile revision conflict' using errcode = '40001';
  end if;
  perform ledgerpulse_internal.require_object('users/' || profile.id, p_avatar_object_key);
  update public.users set display_name = btrim(p_display_name), locale = p_locale,
    theme_preference = p_theme, avatar_object_key = p_avatar_object_key,
    revision = revision + 1, updated_at = clock_timestamp()
    where id = profile.id returning revision into next_revision;
  return next_revision::text;
end $$;

create function ledgerpulse_internal.workspace_tables() returns text[]
language sql immutable set search_path = pg_catalog as $$
  select array[
    'expense_profiles','ledger_profiles','workspace_memberships','expense_wallets','expense_categories',
    'expense_transactions','expense_budgets','expense_recurring_rules','ledger_parties','ledger_accounts',
    'ledger_inventory_items','ledger_vouchers','ledger_voucher_lines','ledger_journals',
    'ledger_journal_lines','ledger_stock_movements','ledger_audit_events'
  ]
$$;

alter table public.users enable row level security;
alter table public.workspaces enable row level security;
alter table private.workspace_commits enable row level security;
revoke all on private.workspace_commits from public, anon, authenticated;
revoke all on public.users, public.workspaces from public, anon, authenticated;
grant select on public.users, public.workspaces to authenticated;
create policy user_read on public.users for select to authenticated using (id = (select auth.uid()));
create policy workspace_read on public.workspaces for select to authenticated
  using (owner_user_id = (select auth.uid()));

-- All application tables are read-only to client roles. Only commands mutate.
do $$
declare relation text;
begin
  foreach relation in array ledgerpulse_internal.workspace_tables() loop
    execute format('alter table public.%I enable row level security', relation);
    execute format('revoke all on public.%I from public, anon, authenticated', relation);
    execute format('grant select on public.%I to authenticated', relation);
    execute format(
      'create policy owner_read on public.%1$I for select to authenticated using (
        exists (select 1 from public.workspaces w where w.id = %1$I.workspace_id
          and w.owner_user_id = (select auth.uid()) and w.lifecycle_state <> ''deleted''))', relation);
  end loop;
end $$;

create function ledgerpulse_internal.wire_row(p_row jsonb) returns jsonb
language sql immutable set search_path = pg_catalog as $$
  select coalesce(jsonb_object_agg(key, case
    when jsonb_typeof(value) = 'number'
      and (key in ('revision','sync_head','quantity','quantity_delta','minimum_stock_qty','tax_rate_pct')
        or right(key,6) = '_minor') then to_jsonb(value #>> '{}')
    else value end), '{}'::jsonb)
  from jsonb_each(p_row)
$$;

-- Only internal commands can open a commit. Change capture uses its operation ID
-- and row scope, so unrelated writes cannot join another workspace's batch.
create function ledgerpulse_internal.capture_change() returns trigger
language plpgsql set search_path = pg_catalog as $$
declare
  operation uuid := nullif(current_setting('ledgerpulse.operation', true), '')::uuid;
  row_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  workspace uuid := coalesce(row_data->>'workspace_id', row_data->>'id')::uuid;
  row_key jsonb;
begin
  if operation is null then return null; end if;
  if tg_table_name = 'workspaces' and tg_op = 'UPDATE'
    and row_data->'revision' = to_jsonb(old)->'revision' then return null; end if;
  row_key := case when tg_table_name = 'workspace_memberships'
    then jsonb_build_object('workspace_id', workspace, 'user_id', row_data->'user_id')
    when tg_table_name in ('expense_profiles','ledger_profiles')
    then jsonb_build_object('workspace_id', workspace)
    else jsonb_build_object('id', row_data->'id') end;
  update private.workspace_commits set changes = changes || jsonb_build_array(jsonb_build_object(
    'table', tg_table_name, 'key', row_key,
    'row', case when tg_op <> 'DELETE' then ledgerpulse_internal.wire_row(row_data) end))
    where workspace_id = workspace and operation_id = operation;
  if not found then raise exception 'missing workspace commit' using errcode = '23514'; end if;
  return null;
end $$;

do $$
declare relation text;
begin
  foreach relation in array array_append(ledgerpulse_internal.workspace_tables(),'workspaces') loop
    execute format('create trigger capture_change after insert or update or delete on public.%I
      for each row execute function ledgerpulse_internal.capture_change()', relation);
  end loop;
end $$;

create function ledgerpulse_internal.start_commit(p_workspace uuid, p_operation uuid, p_actor uuid,
  p_kind text, p_hash bytea) returns bigint
language plpgsql set search_path = pg_catalog as $$
declare next_sequence bigint;
begin
  update public.workspaces set sync_head = sync_head + 1 where id = p_workspace
    returning sync_head into strict next_sequence;
  insert into private.workspace_commits
    (workspace_id, sequence, operation_id, actor_user_id, command_kind, request_hash, changes)
  values (p_workspace, next_sequence, p_operation, p_actor, p_kind, p_hash, '[]');
  perform set_config('ledgerpulse.operation', p_operation::text, true);
  return next_sequence;
end $$;

create function public.ledgerpulse_create_workspace(p_workspace uuid, p_operation uuid, p_type text,
  p_name text, p_currency text, p_time_zone text, p_legal_name text default null) returns jsonb
language plpgsql security definer set search_path = pg_catalog as $$
declare
  actor uuid := public.ledgerpulse_initialize_user();
  scope public.workspaces%rowtype;
  prior private.workspace_commits%rowtype;
  seq bigint;
  signature bytea := sha256(convert_to(jsonb_build_array(
    'create_workspace', p_type, p_name, p_currency, p_time_zone, p_legal_name)::text,'UTF8'));
begin
  if p_workspace is null or p_operation is null or p_type is null
    or p_type not in ('expense','ledger') or (p_type = 'expense' and p_legal_name is not null)
    or not exists (select 1 from pg_timezone_names where name = p_time_zone) then
    raise exception 'invalid workspace request' using errcode = '22023';
  end if;
  insert into public.workspaces (id, owner_user_id, workspace_type, name, currency_code)
    values (p_workspace, actor, p_type, btrim(p_name), p_currency) on conflict (id) do nothing;
  select * into strict scope from public.workspaces where id = p_workspace for update;
  if scope.owner_user_id <> actor then raise exception 'workspace unavailable' using errcode = '42501'; end if;
  if scope.sync_head > 0 then
    select * into prior from private.workspace_commits
      where workspace_id = p_workspace and operation_id = p_operation;
    if not found or prior.actor_user_id is distinct from actor or prior.request_hash <> signature then
      raise exception 'workspace already exists or operation differs' using errcode = '23505';
    end if;
    return jsonb_build_object('sequence',prior.sequence::text,'replayed',true);
  end if;
  seq := ledgerpulse_internal.start_commit(p_workspace,p_operation,actor,'create_workspace',signature);
  -- Record parent first to keep client application FK-safe.
  update private.workspace_commits set changes = jsonb_build_array(jsonb_build_object(
    'table','workspaces','key',jsonb_build_object('id',p_workspace),'row',
    ledgerpulse_internal.wire_row(to_jsonb(scope) || jsonb_build_object('sync_head',seq))))
    where workspace_id = p_workspace and sequence = seq;
  if p_type = 'expense' then
    insert into public.expense_profiles (workspace_id, time_zone) values (p_workspace,p_time_zone);
  else
    insert into public.ledger_profiles (workspace_id,legal_name,time_zone)
      values (p_workspace,btrim(p_legal_name),p_time_zone);
  end if;
  perform set_config('ledgerpulse.operation', '', true);
  return jsonb_build_object('sequence',seq::text,'replayed',false);
end $$;

create function ledgerpulse_internal.assert_balanced() returns trigger
language plpgsql security definer set search_path = pg_catalog as $$
declare posting uuid := case when tg_table_name = 'ledger_journals'
  then (to_jsonb(new)->>'id')::uuid else (to_jsonb(new)->>'journal_id')::uuid end;
begin
  if not exists (
    select 1 from public.ledger_journal_lines
      where workspace_id = new.workspace_id and journal_id = posting
      group by journal_id having count(*) >= 2 and sum(debit_minor) = sum(credit_minor)
  ) then
    raise exception 'journal must have at least two balanced lines' using errcode = '23514';
  end if;
  return null;
end $$;

create constraint trigger journal_balance after insert on public.ledger_journals
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_balanced();
create constraint trigger journal_line_balance after insert on public.ledger_journal_lines
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_balanced();

create function ledgerpulse_internal.assert_voucher_posting() returns trigger
language plpgsql security definer set search_path = pg_catalog as $$
declare
  document_id uuid := case when tg_table_name = 'ledger_vouchers'
    then (to_jsonb(new)->>'id')::uuid else (to_jsonb(new)->>'voucher_id')::uuid end;
  document_status text;
  posting uuid;
  reversed boolean;
begin
  if tg_table_name = 'ledger_journals' and to_jsonb(new)->>'reverses_journal_id' is not null then
    select voucher_id into document_id from public.ledger_journals where workspace_id = new.workspace_id
      and id = (to_jsonb(new)->>'reverses_journal_id')::uuid;
  end if;
  if document_id is null then return null; end if;
  select status into document_status from public.ledger_vouchers
    where workspace_id = new.workspace_id and id = document_id;
  select id into posting from public.ledger_journals
    where workspace_id = new.workspace_id and voucher_id = document_id;
  select exists (select 1 from public.ledger_journals
    where workspace_id = new.workspace_id and reverses_journal_id = posting) into reversed;
  if (document_status = 'posted' and (posting is null or reversed))
    or (document_status = 'voided' and (posting is null or not reversed))
    or (posting is not null and document_status not in ('posted','voided')) then
    raise exception 'voucher status must match its journal and reversal' using errcode = '23514';
  end if;
  return null;
end $$;

create constraint trigger voucher_posting after insert or update on public.ledger_vouchers
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_voucher_posting();
create constraint trigger journal_source_voucher after insert on public.ledger_journals
  deferrable initially deferred for each row execute function ledgerpulse_internal.assert_voucher_posting();

create function ledgerpulse_internal.immutable_fact() returns trigger
language plpgsql set search_path = pg_catalog as $$
begin
  raise exception 'posted accounting facts are immutable' using errcode = '23514';
end $$;

do $$
declare relation text;
begin
  foreach relation in array array['ledger_journals','ledger_journal_lines','ledger_stock_movements','ledger_audit_events'] loop
    execute format('create trigger immutable_fact before update or delete on public.%I
      for each row execute function ledgerpulse_internal.immutable_fact()', relation);
  end loop;
end $$;


create function ledgerpulse_internal.wallet_occurrence(p_workspace uuid, p_data jsonb) returns uuid
language plpgsql set search_path = pg_catalog as $$
declare
  rule public.expense_recurring_rules%rowtype;
  transaction_id uuid := (p_data->>'id')::uuid;
  occurrence date := (p_data->>'occurrence_on')::date;
  zone text;
begin
  select * into rule from public.expense_recurring_rules
    where workspace_id = p_workspace and id = (p_data->>'rule_id')::uuid;
  if not found or rule.deleted_at is not null or not rule.is_active then
    raise exception 'active recurrence not found' using errcode = '23514';
  end if;
  if rule.revision is distinct from (p_data->>'expected_revision')::bigint
     or occurrence is distinct from rule.next_occurrence_on then
    raise exception 'occurrence revision conflict' using errcode = '40001';
  end if;
  if rule.interval_unit not in ('day','week') then
    raise exception 'month and year occurrence generation requires a calendar policy' using errcode = '0A000';
  end if;
  select time_zone into strict zone from public.expense_profiles where workspace_id = p_workspace;
  if occurrence > (clock_timestamp() at time zone zone)::date or occurrence > rule.ends_on then
    raise exception 'occurrence is outside the active schedule' using errcode = '23514';
  end if;
  perform ledgerpulse_internal.require_live_reference('expense_wallets',p_workspace,rule.wallet_id);
  perform ledgerpulse_internal.require_live_reference('expense_wallets',p_workspace,rule.to_wallet_id);
  perform ledgerpulse_internal.require_live_reference('expense_categories',p_workspace,rule.category_id);
  insert into public.expense_transactions
    (id,workspace_id,transaction_type,wallet_id,to_wallet_id,category_id,amount_minor,
     occurred_at,note,recurring_rule_id,occurrence_on)
  values (transaction_id,p_workspace,rule.transaction_type,rule.wallet_id,rule.to_wallet_id,
    rule.category_id,rule.amount_minor,occurrence::timestamp at time zone zone,rule.note,rule.id,occurrence);
  occurrence := occurrence + rule.interval_count * (case rule.interval_unit when 'week' then 7 else 1 end);
  update public.expense_recurring_rules set next_occurrence_on = occurrence,
    is_active = (ends_on is null or occurrence <= ends_on),
    revision = revision + 1, updated_at = clock_timestamp()
    where workspace_id = p_workspace and id = rule.id;
  return transaction_id;
end $$;

create function public.ledgerpulse_command(p_workspace uuid, p_operation uuid,
  p_command text, p_data jsonb, p_protocol integer default 1) returns jsonb
language plpgsql security definer set search_path = pg_catalog as $$
declare
  actor uuid := auth.uid();
  scope public.workspaces%rowtype;
  prior private.workspace_commits%rowtype;
  payload_hash bytea;
  seq bigint;
  target_id uuid;
  expected bigint;
  entity_table text;
  action text;
  replacement uuid;
  doc public.ledger_vouchers%rowtype;
  document_count bigint;
  stock_item uuid;
begin
  if actor is null or p_workspace is null or p_operation is null
    or not coalesce(p_protocol = 1, false) or p_command is null
    or jsonb_typeof(p_data) is distinct from 'object'
    or octet_length(p_data::text) > 131072 then
    raise exception 'invalid command envelope' using errcode = '22023';
  end if;
  select * into scope from public.workspaces where id = p_workspace and owner_user_id = actor for update;
  if not found then raise exception 'workspace unavailable' using errcode = '42501'; end if;
  payload_hash := sha256(convert_to(jsonb_build_array(p_protocol,p_command,p_data)::text,'UTF8'));
  select * into prior from private.workspace_commits where workspace_id = p_workspace and operation_id = p_operation;
  if found then
    if prior.actor_user_id is distinct from actor or prior.request_hash <> payload_hash then
      raise exception 'operation ID reuse' using errcode = '23505';
    end if;
    return jsonb_build_object('sequence',prior.sequence::text,'replayed',true);
  end if;
  if p_command <> 'workspace_state' and scope.lifecycle_state <> 'active' then
    raise exception 'workspace is read-only' using errcode = '42501';
  end if;
  seq := ledgerpulse_internal.start_commit(p_workspace,p_operation,actor,p_command,payload_hash);

  case p_command
    when 'workspace_state' then
      if scope.revision is distinct from (p_data->>'expected_revision')::bigint then
        raise exception 'workspace revision conflict' using errcode = '40001';
      end if;
      if p_data->>'state' is null or p_data->>'state' not in ('active','archived','deleted')
        or (scope.lifecycle_state = 'deleted' and p_data->>'state' = 'deleted') then
        raise exception 'invalid lifecycle transition' using errcode = '23514';
      end if;
      update public.workspaces set lifecycle_state = p_data->>'state',
        archived_at = case when p_data->>'state' = 'archived' then clock_timestamp() end,
        deleted_at = case when p_data->>'state' = 'deleted' then clock_timestamp() end,
        revision = revision + 1, updated_at = clock_timestamp() where id = p_workspace;
      if scope.workspace_type = 'ledger' then
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'workspace','workspace',p_workspace);
      end if;
    when 'rename_workspace' then
      if scope.revision is distinct from (p_data->>'expected_revision')::bigint then
        raise exception 'workspace revision conflict' using errcode = '40001';
      end if;
      update public.workspaces set name = btrim(p_data->>'name'),
        revision = revision + 1, updated_at = clock_timestamp() where id = p_workspace;
      if scope.workspace_type = 'ledger' then
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'workspace','workspace',p_workspace);
      end if;
    when 'set_workspace_currency' then
      if scope.revision is distinct from (p_data->>'expected_revision')::bigint then
        raise exception 'workspace revision conflict' using errcode = '40001';
      end if;
      update public.workspaces set currency_code = p_data->>'currency_code',
        revision = revision + 1, updated_at = clock_timestamp() where id = p_workspace;
      if scope.workspace_type = 'ledger' then
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'workspace','workspace',p_workspace);
      end if;
    when 'write_entity' then
      entity_table := p_data->>'table';
      if entity_table is null or not starts_with(entity_table,scope.workspace_type || '_') then
        raise exception 'wrong entity domain' using errcode = '23514';
      end if;
      target_id := (p_data->>'id')::uuid;
      expected := (p_data->>'expected_revision')::bigint;
      perform ledgerpulse_internal.write_entity(p_workspace,entity_table,target_id,expected,p_data->'fields');
      if scope.workspace_type = 'ledger' then
        if entity_table = 'ledger_voucher_lines' then
          select voucher_id into strict target_id from public.ledger_voucher_lines
            where id = target_id and workspace_id = p_workspace;
          entity_table := 'ledger_vouchers';
        end if;
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'master',entity_table,target_id);
      end if;
    when 'generate_occurrence' then
      if scope.workspace_type <> 'expense' then raise exception 'expense workspace required' using errcode = '23514'; end if;
      perform ledgerpulse_internal.wallet_occurrence(p_workspace,p_data);
    when 'remove_draft_line' then
      select v.* into doc from public.ledger_vouchers v join public.ledger_voucher_lines l
        on l.workspace_id = v.workspace_id and l.voucher_id = v.id
        where v.workspace_id = p_workspace and l.id = (p_data->>'line_id')::uuid;
      if not found or doc.status <> 'draft' or doc.deleted_at is not null then
        raise exception 'editable voucher line not found' using errcode = '23514';
      end if;
      if doc.revision is distinct from (p_data->>'expected_revision')::bigint then
        raise exception 'voucher revision conflict' using errcode = '40001';
      end if;
      delete from public.ledger_voucher_lines where workspace_id = p_workspace and id = (p_data->>'line_id')::uuid;
      update public.ledger_vouchers set revision = revision + 1,updated_at = clock_timestamp()
        where workspace_id = p_workspace and id = doc.id;
      perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'draft','ledger_vouchers',doc.id);
    when 'issue_document' then
      select * into doc from public.ledger_vouchers where workspace_id = p_workspace and id = (p_data->>'id')::uuid;
      if not found or doc.status <> 'draft' or doc.deleted_at is not null
        or doc.document_type not in ('sales_order','purchase_order','estimate') then
        raise exception 'issuable document not found' using errcode = '23514';
      end if;
      if doc.revision is distinct from (p_data->>'expected_revision')::bigint then
        raise exception 'voucher revision conflict' using errcode = '40001';
      end if;
      perform ledgerpulse_internal.require_live_reference('ledger_parties',p_workspace,doc.party_id);
      select count(*)+1 into document_count from public.ledger_vouchers
        where workspace_id = p_workspace and document_type = doc.document_type and document_number is not null;
      update public.ledger_vouchers set status = 'issued',document_number = upper(document_type)||'-'||document_count,
        revision = revision + 1,updated_at = clock_timestamp(),
        party_name_snapshot = (select name from public.ledger_parties where workspace_id = p_workspace and id = doc.party_id)
        where workspace_id = p_workspace and id = doc.id;
      perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'issue','ledger_vouchers',doc.id);
    when 'post_journal','reverse_journal','replace_journal' then
      if scope.workspace_type <> 'ledger' then raise exception 'ledger workspace required' using errcode = '23514'; end if;
      if p_command = 'post_journal' then
        target_id := ledgerpulse_internal.post_journal(p_workspace,actor,p_data);
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'post','ledger_journals',target_id);
      elsif p_command = 'reverse_journal' then
        target_id := ledgerpulse_internal.reverse_journal(p_workspace,actor,p_data);
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'reverse','ledger_journals',target_id);
      else
        target_id := ledgerpulse_internal.reverse_journal(p_workspace,actor,p_data->'reversal');
        replacement := ledgerpulse_internal.post_journal(p_workspace,actor,p_data->'replacement');
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'reverse','ledger_journals',target_id);
        perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'post','ledger_journals',replacement);
      end if;
    when 'stock_movement' then
      if scope.workspace_type <> 'ledger' then raise exception 'ledger workspace required' using errcode = '23514'; end if;
      target_id := (p_data->>'id')::uuid;
      stock_item := (p_data->>'inventory_item_id')::uuid;
      if p_data->>'movement_kind' is null or p_data->>'movement_kind' not in ('opening','adjustment','wastage') then
        raise exception 'invalid direct stock movement' using errcode = '23514';
      end if;
      perform ledgerpulse_internal.require_live_reference('ledger_inventory_items',p_workspace,stock_item);
      insert into public.ledger_stock_movements
        (id,workspace_id,inventory_item_id,movement_kind,quantity_delta,effective_on,note)
        values (target_id,p_workspace,stock_item,p_data->>'movement_kind',
          (p_data->>'quantity_delta')::numeric,(p_data->>'effective_on')::date,p_data->>'note');
      perform ledgerpulse_internal.audit(p_workspace,actor,p_operation,'stock_movement','ledger_stock_movements',target_id);
    else raise exception 'unsupported command' using errcode = '22023';
  end case;

  perform set_config('ledgerpulse.operation', '', true);
  return jsonb_build_object('sequence',seq::text,'replayed',false);
end $$;

create function public.ledgerpulse_pull(p_workspace uuid,p_after bigint,p_limit integer default 100,
  p_protocol integer default 1) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog as $$
declare
  scope public.workspaces%rowtype;
  batches jsonb;
begin
  select * into scope from public.workspaces where id = p_workspace and owner_user_id = auth.uid();
  if not found then raise exception 'workspace unavailable' using errcode = '42501'; end if;
  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'invalid page limit' using errcode = '22023';
  end if;
  if scope.lifecycle_state = 'deleted' then
    return jsonb_build_object('status','deleted','head',scope.sync_head::text);
  end if;
  if p_protocol is distinct from 1 or p_after is null or p_after < 0 or p_after > scope.sync_head
    or exists (select 1 from private.workspace_commits where workspace_id = p_workspace
      and sequence > p_after and changes is null) then
    return jsonb_build_object('status','resnapshot','head',scope.sync_head::text);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('sequence',sequence::text,
    'operation_id',operation_id,'changes',changes) order by sequence),'[]') into batches
    from (select * from private.workspace_commits where workspace_id = p_workspace and sequence > p_after
      order by sequence limit p_limit) page;
  return jsonb_build_object('status','ok','head',scope.sync_head::text,'batches',batches);
end $$;

-- A STABLE function reads all rows and the head under one statement snapshot.
create function public.ledgerpulse_snapshot(p_workspace uuid) returns jsonb
language plpgsql stable security definer set search_path = pg_catalog as $$
declare
  scope public.workspaces%rowtype;
  relation text;
  entity_rows jsonb;
  result jsonb := '{}'::jsonb;
begin
  select * into scope from public.workspaces where id = p_workspace and owner_user_id = auth.uid();
  if not found then raise exception 'workspace unavailable' using errcode = '42501'; end if;
  if scope.lifecycle_state <> 'deleted' then
    foreach relation in array ledgerpulse_internal.workspace_tables() loop
      execute format('select coalesce(jsonb_agg(ledgerpulse_internal.wire_row(to_jsonb(t))),''[]'')
        from public.%I t where workspace_id = $1',relation) into entity_rows using p_workspace;
      result := result || jsonb_build_object(relation,entity_rows);
    end loop;
  end if;
  return jsonb_build_object('protocol',1,'head',scope.sync_head::text,
    'workspace',ledgerpulse_internal.wire_row(to_jsonb(scope)),'tables',result);
end $$;

create view public.ledger_party_activity with (security_invoker = true) as
  select l.workspace_id,l.id,l.party_id,l.journal_id,j.effective_on,l.account_id,
    l.debit_minor,l.credit_minor,j.voucher_id,j.source_kind,j.party_activity_kind,
    j.payment_method,j.receipt_object_key,j.reverses_journal_id,
    coalesce(l.narration,j.narration) as narration
  from public.ledger_journal_lines l
  join public.ledger_journals j on j.workspace_id = l.workspace_id and j.id = l.journal_id
  join public.ledger_accounts a on a.workspace_id = l.workspace_id and a.id = l.account_id
  where a.system_key in ('accounts_receivable','accounts_payable') and l.party_id is not null;

revoke all on public.ledger_party_activity from public, anon, authenticated;
grant select on public.ledger_party_activity to authenticated;
revoke all on all functions in schema ledgerpulse_internal from public, anon, authenticated;

revoke all on function
  public.ledgerpulse_initialize_user(),
  public.ledgerpulse_update_user(bigint,text,text,text,text),
  public.ledgerpulse_create_workspace(uuid,uuid,text,text,text,text,text),
  public.ledgerpulse_command(uuid,uuid,text,jsonb,integer),
  public.ledgerpulse_pull(uuid,bigint,integer,integer),
  public.ledgerpulse_snapshot(uuid)
from public, anon, authenticated;
grant execute on function
  public.ledgerpulse_initialize_user(),
  public.ledgerpulse_update_user(bigint,text,text,text,text),
  public.ledgerpulse_create_workspace(uuid,uuid,text,text,text,text,text),
  public.ledgerpulse_command(uuid,uuid,text,jsonb,integer),
  public.ledgerpulse_pull(uuid,bigint,integer,integer),
  public.ledgerpulse_snapshot(uuid)
to authenticated;

commit;
