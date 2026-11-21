alter table public.ledger_entries
  add column payment_method text check (payment_method in ('cash', 'bank', 'upi', 'cheque')),
  add column entry_kind text check (entry_kind in ('credit', 'payment'));
