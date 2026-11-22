begin;
select '1..1';

insert into auth.users (id, email, raw_user_meta_data) values
  ('10000000-0000-4000-8000-000000000001','ledgerpulse-test-a@example.invalid','{"name":"Fixture A"}'),
  ('10000000-0000-4000-8000-000000000002','ledgerpulse-test-b@example.invalid','{"name":"Fixture B"}');

-- Fixtures are rolled back. Never run this suite against a hosted database.
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true) is not null as fixture_a \gset

do $$
declare
  expense constant uuid := '20000000-0000-4000-8000-000000000001';
  ledger constant uuid := '20000000-0000-4000-8000-000000000002';
  other_wallet constant uuid := '30000000-0000-4000-8000-000000000002';
  wallet constant uuid := '30000000-0000-4000-8000-000000000001';
  posting constant uuid := '50000000-0000-4000-8000-000000000001';
  operation uuid := gen_random_uuid();
  request jsonb;
  receipt jsonb;
begin
  if public.ledgerpulse_initialize_user() <> public.ledgerpulse_initialize_user()
    or (select count(*) from public.users) <> 1
    or (select display_name from public.users) <> 'Fixture A' then
    raise exception 'initialization must preserve the existing self row';
  end if;
  perform public.ledgerpulse_create_workspace(expense,operation,'expense','Expense','INR','UTC');
  receipt := public.ledgerpulse_create_workspace(expense,operation,'expense','Expense','INR','UTC');
  if receipt->>'replayed' <> 'true' then raise exception 'workspace retry was not idempotent'; end if;
  perform public.ledgerpulse_create_workspace(ledger,gen_random_uuid(),'ledger','Ledger','INR','UTC','Fixture Business');
  perform public.ledgerpulse_create_workspace('20000000-0000-4000-8000-000000000003',
    gen_random_uuid(),'expense','Another Expense','INR','UTC');
  perform public.ledgerpulse_command('20000000-0000-4000-8000-000000000003',
    gen_random_uuid(),'set_workspace_currency','{"currency_code":"JPY","expected_revision":1}');
  if (select count(*) from public.workspaces) <> 3
    or (select count(*) from public.expense_profiles) <> 2
    or (select count(*) from public.ledger_profiles) <> 1 then
    raise exception 'workspaces or typed profiles were not created';
  end if;

  perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',jsonb_build_object(
    'table','expense_wallets','id',wallet,'expected_revision',0,'fields',jsonb_build_object('name','Cash','wallet_type','cash')));
  begin
    perform public.ledgerpulse_command(expense,gen_random_uuid(),'set_workspace_currency',
      '{"currency_code":"USD","expected_revision":1}');
    raise exception 'wallet did not lock workspace currency';
  exception when check_violation then null;
  end;
  perform public.ledgerpulse_command('20000000-0000-4000-8000-000000000003',gen_random_uuid(),
    'write_entity',jsonb_build_object('table','expense_wallets','id',other_wallet,'expected_revision',0,
    'fields',jsonb_build_object('name','Other Cash','wallet_type','cash')));
  request := jsonb_build_object('table','expense_transactions','id','40000000-0000-4000-8000-000000000001',
    'expected_revision',0,'fields',jsonb_build_object('transaction_type','expense','wallet_id',wallet,
    'amount_minor','9007199254740993','occurred_at','2026-01-01T00:00:00Z'));
  operation := gen_random_uuid();
  perform public.ledgerpulse_command(expense,operation,'write_entity',request);
  receipt := public.ledgerpulse_command(expense,operation,'write_entity',request);
  if receipt->>'replayed' <> 'true' or (select count(*) from public.expense_transactions) <> 1 then
    raise exception 'expense replay duplicated a transaction';
  end if;
  if public.ledgerpulse_snapshot(expense)#>>'{tables,expense_transactions,0,amount_minor}' <> '9007199254740993' then
    raise exception 'snapshot minor-unit precision did not round trip';
  end if;
  begin
    perform public.ledgerpulse_command(expense,operation,'write_entity',request || '{"unexpected":true}');
    raise exception 'operation reuse accepted a different payload';
  exception when unique_violation then null;
  end;
  begin
    perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',
      jsonb_set(jsonb_set(request, '{expected_revision}', '1'), '{fields,wallet_id}', to_jsonb(other_wallet)));
    raise exception 'cross-workspace wallet accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',request);
    raise exception 'cross-domain transaction accepted';
  exception when check_violation then null;
  end;
  begin
    update public.workspaces set owner_user_id = '10000000-0000-4000-8000-000000000002' where id = expense;
    raise exception 'workspace owner change permitted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.workspace_memberships(workspace_id,user_id,role) values
      (expense,'10000000-0000-4000-8000-000000000002','admin');
    raise exception 'client granted membership';
  exception when insufficient_privilege then null;
  end;

  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',
    '{"table":"ledger_accounts","id":"60000000-0000-4000-8000-000000000001","expected_revision":0,
      "fields":{"code":"1001","name":"Cash","account_type":"asset"}}');
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',
    '{"table":"ledger_accounts","id":"60000000-0000-4000-8000-000000000002","expected_revision":0,
      "fields":{"code":"3001","name":"Equity","account_type":"equity"}}');
  request := jsonb_build_object('id',posting,'source_kind','opening','effective_on','2026-01-01','lines',
    '[{"id":"70000000-0000-4000-8000-000000000001","account_id":"60000000-0000-4000-8000-000000000001","debit_minor":"500"},
      {"id":"70000000-0000-4000-8000-000000000002","account_id":"60000000-0000-4000-8000-000000000002","credit_minor":"500"}]'::jsonb);
  begin
    perform public.ledgerpulse_command(ledger,gen_random_uuid(),'post_journal',
      jsonb_set(request,'{lines,1,credit_minor}','"499"'));
    raise exception 'unbalanced journal was accepted';
  exception when check_violation then null;
  end;
  if exists (select 1 from public.ledger_journals) then raise exception 'failed posting left rows'; end if;
  operation := gen_random_uuid();
  perform public.ledgerpulse_command(ledger,operation,'post_journal',request);
  receipt := public.ledgerpulse_command(ledger,operation,'post_journal',request);
  if receipt->>'replayed' <> 'true' or (select count(*) from public.ledger_journal_lines) <> 2 then
    raise exception 'posting replay duplicated lines';
  end if;
  if jsonb_array_length(public.ledgerpulse_pull(ledger,(receipt->>'sequence')::bigint-1)#>'{batches,0,changes}') <> 4 then
    raise exception 'journal, lines and audit should share a batch';
  end if;
  begin
    update public.ledger_journal_lines set debit_minor = 10 where journal_id = posting;
    raise exception 'raw posted edit succeeded';
  exception when insufficient_privilege then null;
  end;
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'reverse_journal',jsonb_build_object(
    'id','50000000-0000-4000-8000-000000000002','journal_id',posting,'effective_on','2026-01-02'));
  if (select count(*) from public.ledger_journals) <> 2 or exists (
    select 1 from public.ledger_journal_lines group by account_id having sum(debit_minor-credit_minor) <> 0
  ) then raise exception 'reversal did not zero each account while retaining the original'; end if;
  begin
    perform public.ledgerpulse_command(ledger,gen_random_uuid(),'reverse_journal',jsonb_build_object(
      'id','50000000-0000-4000-8000-000000000003','journal_id',posting,'effective_on','2026-01-02'));
    raise exception 'duplicate reversal accepted';
  exception when unique_violation then null;
  end;
  perform public.ledgerpulse_command(expense,gen_random_uuid(),'workspace_state','{"state":"deleted","expected_revision":1}');
  if exists(select 1 from public.expense_transactions) or public.ledgerpulse_pull(expense,0)->>'status' <> 'deleted' then
    raise exception 'deleted workspace exposes finance rows';
  end if;
  perform public.ledgerpulse_command(expense,gen_random_uuid(),'workspace_state','{"state":"active","expected_revision":2}');
  if (select count(*) from public.expense_transactions) <> 1 then raise exception 'restore lost rows'; end if;

  insert into storage.objects(bucket_id,name)
    values ('ledgerpulse-private','workspaces/20000000-0000-4000-8000-000000000001/90000000-0000-4000-8000-000000000001');
  perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',jsonb_build_object(
    'table','expense_transactions','id','40000000-0000-4000-8000-000000000001','expected_revision',1,
    'fields',jsonb_build_object('receipt_object_key',
      'workspaces/20000000-0000-4000-8000-000000000001/90000000-0000-4000-8000-000000000001')));
  begin
    insert into storage.objects(bucket_id,name)
      values ('ledgerpulse-private','users/10000000-0000-4000-8000-000000000002/90000000-0000-4000-8000-000000000001');
    raise exception 'foreign user object path accepted';
  exception when insufficient_privilege then null;
  end;
  if public.ledgerpulse_update_user(1,'Updated A','en','dark') <> '2'
    or public.ledgerpulse_update_user(1,'Updated A','en','dark') <> '2' then
    raise exception 'user update retry changed the revision';
  end if;

  perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',jsonb_build_object(
    'table','expense_recurring_rules','id','a0000000-0000-4000-8000-000000000001','expected_revision',0,
    'fields',jsonb_build_object('wallet_id',wallet,'transaction_type','expense','amount_minor','12',
      'anchor_on','2026-01-01','next_occurrence_on','2026-01-01','interval_unit','day','interval_count',1)));
  operation := gen_random_uuid();
  request := '{"id":"40000000-0000-4000-8000-000000000003",
    "rule_id":"a0000000-0000-4000-8000-000000000001","expected_revision":1,"occurrence_on":"2026-01-01"}';
  receipt := public.ledgerpulse_command(expense,operation,'generate_occurrence',request);
  if (select next_occurrence_on from public.expense_recurring_rules) <> date '2026-01-02'
    or jsonb_array_length(public.ledgerpulse_pull(expense,(receipt->>'sequence')::bigint-1)#>'{batches,0,changes}') <> 2 then
    raise exception 'recurring occurrence and advancement are not one batch';
  end if;

  perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',jsonb_build_object(
    'table','expense_budgets','id',gen_random_uuid(),'expected_revision',0,
    'fields',jsonb_build_object('period_type','weekly','amount_minor','500','start_on','2026-01-01')));
  if not exists (select 1 from public.expense_budgets where period_type = 'weekly' and amount_minor = 500) then
    raise exception 'weekly budget was not saved';
  end if;

  declare
    calendar_case record;
    calendar_rule uuid;
    calendar_tx uuid;
  begin
    for calendar_case in select * from (values
      ('month',date '2024-01-31',date '2024-02-29'),
      ('year',date '2024-02-29',date '2025-02-28')
    ) cases(unit, due_on, advance_to) loop
      calendar_rule := gen_random_uuid();
      calendar_tx := gen_random_uuid();
      perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',jsonb_build_object(
        'table','expense_recurring_rules','id',calendar_rule,'expected_revision',0,
        'fields',jsonb_build_object('wallet_id',wallet,'transaction_type','expense','amount_minor','12',
          'anchor_on',calendar_case.due_on,'next_occurrence_on',calendar_case.due_on,
          'interval_unit',calendar_case.unit,'interval_count',1)));
      operation := gen_random_uuid();
      request := jsonb_build_object('id',calendar_tx,'rule_id',calendar_rule,
        'expected_revision',1,'occurrence_on',calendar_case.due_on);
      receipt := public.ledgerpulse_command(expense,operation,'generate_occurrence',request);
      if public.ledgerpulse_command(expense,operation,'generate_occurrence',request)->>'sequence'
           is distinct from receipt->>'sequence'
         or not exists (select 1 from public.expense_recurring_rules
           where id = calendar_rule and next_occurrence_on = calendar_case.advance_to and revision = 2)
         or (select count(*) from public.expense_transactions where recurring_rule_id = calendar_rule) <> 1 then
        raise exception 'calendar occurrence or retry differs for %', calendar_case.unit;
      end if;
    end loop;
  end;

  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',
    '{"table":"ledger_inventory_items","id":"80000000-0000-4000-8000-000000000001","expected_revision":0,
      "fields":{"sku":"ITEM","name":"Item","unit":"piece"}}');
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',
    '{"table":"ledger_accounts","id":"60000000-0000-4000-8000-000000000003","expected_revision":0,
      "fields":{"code":"5001","name":"Purchases","account_type":"expense"}}');
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',
    '{"table":"ledger_vouchers","id":"b0000000-0000-4000-8000-000000000001","expected_revision":0,
      "fields":{"document_type":"purchase","document_on":"2026-01-01","subtotal_minor":"100",
        "total_minor":"100","payment_method":"cash"}}');
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'write_entity',
    '{"table":"ledger_voucher_lines","id":"b0000000-0000-4000-8000-000000000002","expected_revision":0,
      "fields":{"voucher_id":"b0000000-0000-4000-8000-000000000001","line_no":1,
        "inventory_item_id":"80000000-0000-4000-8000-000000000001","description_snapshot":"Item",
        "unit_snapshot":"piece","quantity":"1.25","unit_price_minor":"80","line_total_minor":"100"}}');
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'post_journal',
    '{"id":"50000000-0000-4000-8000-000000000004","source_kind":"voucher",
      "voucher_id":"b0000000-0000-4000-8000-000000000001","expected_revision":2,
      "lines":[
        {"id":"70000000-0000-4000-8000-000000000003","account_id":"60000000-0000-4000-8000-000000000003","debit_minor":"100"},
        {"id":"70000000-0000-4000-8000-000000000004","account_id":"60000000-0000-4000-8000-000000000001","credit_minor":"100"}
      ]}');
  if (select status from public.ledger_vouchers) <> 'posted'
    or (select quantity_delta from public.ledger_stock_movements) <> 1.25 then
    raise exception 'voucher posting did not write its stock effect';
  end if;
  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'reverse_journal',
    '{"id":"50000000-0000-4000-8000-000000000005","journal_id":"50000000-0000-4000-8000-000000000004",
      "effective_on":"2026-01-02"}');
  if (select status from public.ledger_vouchers) <> 'voided'
    or (select sum(quantity_delta) from public.ledger_stock_movements) <> 0 then
    raise exception 'voucher reversal did not reverse its stock effect';
  end if;

  -- Two intents from the same base revision. The later stale edit must keep
  -- the tombstone, preserve the original amount and leave the feed head fixed.
  perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',
    '{"table":"expense_transactions","id":"40000000-0000-4000-8000-000000000001",
      "expected_revision":2,"fields":{"deleted_at":true}}');
  receipt := public.ledgerpulse_snapshot(expense);
  begin
    perform public.ledgerpulse_command(expense,gen_random_uuid(),'write_entity',
      '{"table":"expense_transactions","id":"40000000-0000-4000-8000-000000000001",
        "expected_revision":2,"fields":{"amount_minor":"1","deleted_at":null}}');
    raise exception 'stale device resurrected a tombstone';
  exception when serialization_failure then null;
  end;
  if (public.ledgerpulse_snapshot(expense)->>'head') is distinct from (receipt->>'head')
    or not exists (select 1 from public.expense_transactions
      where id = '40000000-0000-4000-8000-000000000001' and deleted_at is not null
        and revision = 3 and amount_minor = 9007199254740993) then
    raise exception 'conflict changed the accepted expense or feed head';
  end if;

  perform public.ledgerpulse_command(ledger,gen_random_uuid(),'post_journal',
    '{"id":"50000000-0000-4000-8000-000000000006","source_kind":"manual","effective_on":"2026-01-01",
      "lines":[
        {"id":"70000000-0000-4000-8000-000000000005","account_id":"60000000-0000-4000-8000-000000000001","debit_minor":"10"},
        {"id":"70000000-0000-4000-8000-000000000006","account_id":"60000000-0000-4000-8000-000000000002","credit_minor":"10"}
      ]}');
  request := '{
    "reversal":{"id":"50000000-0000-4000-8000-000000000007",
      "journal_id":"50000000-0000-4000-8000-000000000006","effective_on":"2026-01-03"},
    "replacement":{"id":"50000000-0000-4000-8000-000000000008",
      "source_kind":"manual","effective_on":"2026-01-03","lines":[
        {"id":"70000000-0000-4000-8000-000000000007","account_id":"60000000-0000-4000-8000-000000000001","debit_minor":"15"},
        {"id":"70000000-0000-4000-8000-000000000008","account_id":"60000000-0000-4000-8000-000000000002","credit_minor":"15"}
      ]}
    }';
  receipt := public.ledgerpulse_snapshot(ledger);
  begin
    perform public.ledgerpulse_command(ledger,gen_random_uuid(),'replace_journal',
      jsonb_set(request,'{replacement,lines,1,credit_minor}','"14"'));
    raise exception 'unbalanced correction was accepted';
  exception when check_violation then null;
  end;
  if (public.ledgerpulse_snapshot(ledger)->>'head') is distinct from (receipt->>'head')
    or exists (select 1 from public.ledger_journals where
      reverses_journal_id = '50000000-0000-4000-8000-000000000006') then
    raise exception 'failed correction left a reversal or advanced the head';
  end if;
  operation := gen_random_uuid();
  receipt := public.ledgerpulse_command(ledger,operation,'replace_journal',request);
  if (public.ledgerpulse_command(ledger,operation,'replace_journal',request)->>'replayed') is distinct from 'true'
    or jsonb_array_length(public.ledgerpulse_pull(ledger,(receipt->>'sequence')::bigint-1)#>'{batches,0,changes}') is distinct from 8 then
    raise exception 'correction and audit were not one idempotent batch';
  end if;
end $$;

reset role;
insert into public.workspace_memberships (workspace_id,user_id,role,state,activated_at) values
  ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','admin','active',now());
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true) is not null as fixture_b \gset
do $$
begin
  if exists (select 1 from public.workspaces) or exists (select 1 from public.expense_wallets)
    or exists (select 1 from public.workspace_memberships) or exists (select 1 from public.ledger_party_activity)
    or exists (select 1 from storage.objects where bucket_id = 'ledgerpulse-private')
    or (select count(*) from public.users) <> 1 then
    raise exception 'tenancy or deferred membership isolation failed';
  end if;
  begin
    perform public.ledgerpulse_command('20000000-0000-4000-8000-000000000001',
      gen_random_uuid(),'rename_workspace','{"name":"Denied","expected_revision":3}');
    raise exception 'foreign command succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
set constraints all immediate;
do $$
begin
  begin
    insert into public.workspaces(id,owner_user_id,workspace_type,name,currency_code)
      values ('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001','expense','Missing subtype','INR');
    raise exception 'workspace without subtype accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.ledger_profiles(workspace_id,legal_name)
      values ('20000000-0000-4000-8000-000000000001','Wrong subtype');
    raise exception 'wrong subtype accepted';
  exception when foreign_key_violation then null;
  end;
  begin
    insert into public.expense_transactions (id,workspace_id,transaction_type,wallet_id,amount_minor,occurred_at)
      values ('40000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','expense',
        '30000000-0000-4000-8000-000000000002',1,now());
    raise exception 'database accepted a cross-workspace foreign key';
  exception when foreign_key_violation then null;
  end;
end $$;
select 'ok 1 - LedgerPulse database contract';
rollback;
