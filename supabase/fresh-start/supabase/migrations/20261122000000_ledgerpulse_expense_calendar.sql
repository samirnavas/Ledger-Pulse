begin;

alter table public.expense_budgets
  drop constraint expense_budgets_period_type_check,
  add constraint expense_budgets_period_type_check
    check (period_type in ('weekly','monthly','quarterly','yearly'));

create or replace function ledgerpulse_internal.wallet_occurrence(p_workspace uuid, p_data jsonb) returns uuid
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
  -- Advance from the previous occurrence, clamping short months as Dart does.
  occurrence := case rule.interval_unit
    when 'day' then occurrence + rule.interval_count
    when 'week' then occurrence + 7 * rule.interval_count
    when 'month' then (occurrence + make_interval(months => rule.interval_count))::date
    when 'year' then (occurrence + make_interval(years => rule.interval_count))::date
  end;
  update public.expense_recurring_rules set next_occurrence_on = occurrence,
    is_active = (ends_on is null or occurrence <= ends_on),
    revision = revision + 1, updated_at = clock_timestamp()
    where workspace_id = p_workspace and id = rule.id;
  return transaction_id;
end $$;

commit;
