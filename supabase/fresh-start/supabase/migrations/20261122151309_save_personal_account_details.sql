begin;

alter table public.users
  add column phone_number text,
  add column email text,
  add column business_name text,
  add column address text,
  add column gstin text,
  add column business_type text,
  add column bank_name text,
  add column bank_account_number text,
  add column bank_ifsc text,
  add column upi_id text;

-- The users table grants clients SELECT only. Keep writes scoped to the
-- signed-in account and preserve revisions shared with ledgerpulse_update_user.
create function public.ledgerpulse_save_account(p_account_id uuid, p_details jsonb) returns void
language plpgsql security definer set search_path = pg_catalog as $$
declare
  actor uuid := auth.uid();
  details public.users%rowtype;
begin
  if actor is null or actor is distinct from p_account_id then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  details := jsonb_populate_record(null::public.users, p_details);
  update public.users as u
    set display_name = btrim(details.display_name),
        phone_number = details.phone_number,
        email = details.email,
        business_name = details.business_name,
        address = details.address,
        gstin = details.gstin,
        business_type = details.business_type,
        bank_name = details.bank_name,
        bank_account_number = details.bank_account_number,
        bank_ifsc = details.bank_ifsc,
        upi_id = details.upi_id,
        revision = u.revision + 1,
        updated_at = clock_timestamp()
  where u.id = actor
    and row(u.display_name, u.phone_number, u.email, u.business_name, u.address,
            u.gstin, u.business_type, u.bank_name, u.bank_account_number,
            u.bank_ifsc, u.upi_id)
     is distinct from
        row(btrim(details.display_name), details.phone_number, details.email,
            details.business_name, details.address, details.gstin,
            details.business_type, details.bank_name, details.bank_account_number,
            details.bank_ifsc, details.upi_id);
  if not found and not exists (select 1 from public.users where id = actor) then
    raise exception 'account profile unavailable' using errcode = '23503';
  end if;
end $$;

revoke all on function public.ledgerpulse_save_account(uuid,jsonb) from public, anon;
grant execute on function public.ledgerpulse_save_account(uuid,jsonb) to authenticated;

commit;
