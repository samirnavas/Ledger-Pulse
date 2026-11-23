begin;

lock table public.users in access exclusive mode;

-- A previous version stored these fields without a workspace ID. Refuse to
-- discard data if this migration is run on a database that has any such rows.
do $$
begin
  if exists (
    select 1 from public.users
    where coalesce(nullif(btrim(business_name), ''), nullif(btrim(address), ''),
      nullif(btrim(gstin), ''), nullif(btrim(business_type), ''),
      nullif(btrim(bank_name), ''), nullif(btrim(bank_account_number), ''),
      nullif(btrim(bank_ifsc), ''), nullif(btrim(upi_id), '')) is not null
  ) then
    raise exception 'Business details require an explicit ledger workspace assignment before removing these columns';
  end if;
end $$;

create or replace function public.ledgerpulse_save_account(p_account_id uuid, p_details jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog as $$
declare
  actor uuid := auth.uid();
  next_display_name text := btrim(p_details->>'display_name');
  next_phone_number text := p_details->>'phone_number';
  next_email text := p_details->>'email';
begin
  if actor is null or actor is distinct from p_account_id then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  update public.users as u
    set display_name = next_display_name,
        phone_number = next_phone_number,
        email = next_email,
        revision = u.revision + 1,
        updated_at = clock_timestamp()
  where u.id = actor
    and row(u.display_name, u.phone_number, u.email)
      is distinct from row(next_display_name,
        next_phone_number, next_email);
  if not found and not exists (select 1 from public.users where id = actor) then
    raise exception 'account profile unavailable' using errcode = '23503';
  end if;
end $$;

alter table public.users
  drop column business_name,
  drop column address,
  drop column gstin,
  drop column business_type,
  drop column bank_name,
  drop column bank_account_number,
  drop column bank_ifsc,
  drop column upi_id;

commit;
