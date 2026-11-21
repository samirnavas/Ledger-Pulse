-- Run against an authorized read-only snapshot before any data repair.
-- Output is grouped by workspace and contains counts and minor-unit totals.
BEGIN READ ONLY;

WITH classified AS (
  SELECT e.*,
    substring(e.note FROM '^(?:Reversal|Offset): Voided entry #([^ ]+)') AS original_id
  FROM public.ledger_entries e
), effective AS (
  SELECT e.*,
    (original.id IS NOT NULL
      AND (original.is_voided OR original.is_deleted)
      AND e.type <> original.type
      AND e.amount_in_cents = original.amount_in_cents
      AND e.note ~ '^(Reversal: Voided entry #[^ ]+|Offset: Voided entry #[^ ]+( \(.*\))?)$'
    ) AS legacy_offset
  FROM classified e
  LEFT JOIN public.ledger_entries original
    ON original.id = e.original_id AND original.company_id = e.company_id
    AND original.party_id = e.party_id
), totals AS (
  SELECT company_id, party_id, sum(CASE
    WHEN is_deleted OR is_voided OR legacy_offset THEN 0
    WHEN type = 'gave' THEN amount_in_cents
    ELSE -amount_in_cents
  END) AS calculated
  FROM effective
  GROUP BY company_id, party_id
), party_account_totals AS (
  SELECT l.company_id, l.party_id,
    sum(l.debit_in_cents - l.credit_in_cents) AS calculated
  FROM public.journal_lines l
  JOIN public.journals j ON j.id = l.journal_id AND j.company_id = l.company_id
  WHERE NOT l.is_deleted AND NOT j.is_deleted AND j.status = 'posted'
    AND l.party_id IS NOT NULL
    AND l.account_id IN (l.company_id || '_acc_ar', l.company_id || '_acc_ap')
  GROUP BY l.company_id, l.party_id
), issues AS (
  SELECT p.company_id, 'cached party balance differs' AS issue,
    t.calculated - p.net_balance_in_cents AS variance
  FROM public.parties p JOIN totals t ON t.party_id = p.id AND t.company_id = p.company_id
  WHERE NOT p.is_deleted AND t.calculated <> p.net_balance_in_cents
  UNION ALL
  SELECT p.company_id, 'party ledger and AR/AP postings differ',
    coalesce(t.calculated, p.net_balance_in_cents) - coalesce(a.calculated, 0)
  FROM public.parties p
  LEFT JOIN totals t ON t.party_id = p.id AND t.company_id = p.company_id
  LEFT JOIN party_account_totals a ON a.party_id = p.id AND a.company_id = p.company_id
  WHERE coalesce(t.calculated, p.net_balance_in_cents) <> coalesce(a.calculated, 0)
  UNION ALL
  SELECT p.company_id, 'opening balance without entry history', p.net_balance_in_cents
  FROM public.parties p
  LEFT JOIN totals t ON t.party_id = p.id AND t.company_id = p.company_id
  WHERE NOT p.is_deleted AND t.party_id IS NULL AND p.net_balance_in_cents <> 0
  UNION ALL
  SELECT p.company_id, 'archived party with outstanding balance',
    coalesce(t.calculated, p.net_balance_in_cents)
  FROM public.parties p
  LEFT JOIN totals t ON t.party_id = p.id AND t.company_id = p.company_id
  WHERE p.is_deleted AND coalesce(t.calculated, p.net_balance_in_cents) <> 0
  UNION ALL
  SELECT e.company_id, 'offset note without verified original', e.amount_in_cents
  FROM effective e
  WHERE NOT e.is_deleted AND e.original_id IS NOT NULL AND NOT e.legacy_offset
  UNION ALL
  SELECT e.company_id, 'verified legacy offset has a posted journal', e.amount_in_cents
  FROM effective e JOIN public.journals j
    ON j.id = 'jnl_entry_' || e.id AND j.company_id = e.company_id
  WHERE e.legacy_offset AND j.status = 'posted' AND NOT j.is_deleted
  UNION ALL
  SELECT e.company_id, 'standalone entry and journal disagree', e.amount_in_cents
  FROM effective e
  LEFT JOIN public.journals j
    ON j.id = 'jnl_entry_' || e.id AND j.company_id = e.company_id
  WHERE NOT e.legacy_offset AND e.original_id IS NULL
    AND left(e.id, 10) <> 'vch_entry_' AND left(e.id, 5) <> 'open_'
    AND (CASE WHEN e.is_deleted OR e.is_voided
          THEN j.status = 'posted' AND NOT j.is_deleted
          ELSE j.id IS NULL OR j.status <> 'posted' OR j.is_deleted
            OR j.total_amount_in_cents <> e.amount_in_cents
         END)
  UNION ALL
  SELECT e.company_id, 'entry belongs to a non-ledger profile', e.amount_in_cents
  FROM effective e JOIN public.companies c ON c.id = e.company_id
  WHERE NOT e.is_deleted AND c.mode <> 'ledger'
  UNION ALL
  SELECT j.company_id, 'posted journal is unbalanced or empty',
    sum(coalesce(l.debit_in_cents, 0) - coalesce(l.credit_in_cents, 0))
  FROM public.journals j
  LEFT JOIN public.journal_lines l
    ON l.journal_id = j.id AND l.company_id = j.company_id AND NOT l.is_deleted
  WHERE NOT j.is_deleted AND j.status = 'posted'
  GROUP BY j.company_id, j.id
  HAVING count(l.id) = 0
    OR sum(coalesce(l.debit_in_cents, 0)) <> sum(coalesce(l.credit_in_cents, 0))
)
SELECT company_id, issue, count(*) AS records, sum(abs(variance)) AS absolute_minor_units
FROM issues
GROUP BY company_id, issue
ORDER BY company_id, issue;

ROLLBACK;
