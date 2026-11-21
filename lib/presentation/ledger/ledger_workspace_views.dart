import 'widgets/ledger_date_filter.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/local/database.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import 'add_entry_bottom_sheet.dart';
import 'widgets/party_transaction_voucher_sheet.dart';

typedef _ActivityRow = ({Party party, LedgerEntry entry, bool archived});
typedef _ActivityFilter = ({
  int limit,
  bool includeVoids,
  String? partyId,
  EntryType? type,
  DateTime? start,
  DateTime? end,
  String search,
});

final ledgerActivityProvider = StreamProvider.autoDispose<List<_ActivityRow>>((
  ref,
) {
  final company = ref.watch(activeCompanyProvider);
  if (!company.isLedger) return Stream.value(const []);
  return _watchActivity(ref.watch(appDatabaseProvider), company.id, const (
    limit: 5,
    includeVoids: false,
    partyId: null,
    type: null,
    start: null,
    end: null,
    search: '',
  ));
});

final ledgerActivityPageProvider = StreamProvider.autoDispose
    .family<List<_ActivityRow>, _ActivityFilter>((ref, filter) {
      final company = ref.watch(activeCompanyProvider);
      if (!company.isLedger) return Stream.value(const []);
      final db = ref.watch(appDatabaseProvider);
      return _watchActivity(db, company.id, filter);
    });

Stream<List<_ActivityRow>> _watchActivity(
  AppDatabase db,
  String companyId,
  _ActivityFilter filter,
) {
  return db
      .customSelect(
        '''
    WITH visible AS (
      SELECT e.*, SUM(CASE WHEN e.is_voided THEN 0
          WHEN e.type = 'gave' THEN e.amount_in_cents ELSE -e.amount_in_cents END)
        OVER (PARTITION BY e.party_id ORDER BY e.date, e.created_at, e.id)
        AS running_balance
      FROM ledger_entries e
      WHERE e.company_id = ? AND NOT e.is_deleted
        AND NOT EXISTS (
          SELECT 1 FROM ledger_entries original
          WHERE original.id = CASE
            WHEN substr(e.note, 1, 24) = 'Reversal: Voided entry #'
              THEN substr(e.note, 25)
            WHEN substr(e.note, 1, 22) = 'Offset: Voided entry #' THEN
              CASE WHEN instr(substr(e.note, 23), ' (') > 0 AND substr(e.note, -1) = ')'
                THEN substr(e.note, 23, instr(substr(e.note, 23), ' (') - 1)
                ELSE substr(e.note, 23) END
            END
            AND instr(original.id, ' ') = 0
            AND original.company_id = e.company_id
            AND original.party_id = e.party_id
            AND (original.is_voided OR original.is_deleted)
            AND original.type <> e.type
            AND original.amount_in_cents = e.amount_in_cents
        )
    )
    SELECT visible.*, p.name AS party_name, p.phone_number AS party_phone,
      p.type AS party_type, p.net_balance_in_cents AS party_balance,
      p.last_updated AS party_updated, p.is_deleted AS archived
    FROM visible JOIN parties p ON visible.party_id = p.id AND p.company_id = visible.company_id
    WHERE ${filter.includeVoids ? '1 = 1' : 'NOT visible.is_voided'}
      ${filter.partyId == null ? '' : 'AND visible.party_id = ?'}
      ${filter.type == null ? '' : 'AND visible.type = ?'}
      ${filter.start == null ? '' : 'AND visible.date >= ?'}
      ${filter.end == null ? '' : 'AND visible.date < ?'}
      ${filter.search.isEmpty ? '' : "AND (instr(lower(p.name), ?) > 0 OR instr(lower(coalesce(visible.note, '')), ?) > 0)"}
    ORDER BY visible.date DESC, visible.created_at DESC, visible.id DESC
    LIMIT ?
    ''',
        variables: [
          Variable.withString(companyId),
          if (filter.partyId != null) Variable.withString(filter.partyId!),
          if (filter.type != null) Variable.withString(filter.type!.name),
          if (filter.start != null) Variable.withDateTime(filter.start!),
          if (filter.end != null) Variable.withDateTime(filter.end!),
          if (filter.search.isNotEmpty) ...[
            Variable.withString(filter.search),
            Variable.withString(filter.search),
          ],
          Variable.withInt(filter.limit),
        ],
        readsFrom: {db.ledgerEntries, db.parties},
      )
      .watch()
      .map(
        (result) => result.map((item) {
          final row = db.ledgerEntries.map(item.data);
          return (
            archived: item.read<bool>('archived'),
            party: Party(
              id: row.partyId,
              name: item.read<String>('party_name'),
              phoneNumber: item.read<String>('party_phone'),
              type: PartyType.values.byName(item.read<String>('party_type')),
              netBalanceInCents: item.read<int>('party_balance'),
              lastUpdated: item.read<DateTime>('party_updated'),
            ),
            entry: LedgerEntry(
              id: row.id,
              partyId: row.partyId,
              type: row.type,
              amountInCents: row.amountInCents,
              date: row.date,
              note: row.note,
              paymentMethod: LedgerPaymentMethod.fromName(row.paymentMethod),
              kind: row.entryKind,
              receiptPhotoUrl: row.receiptPhotoUrl,
              isVoided: row.isVoided,
              runningBalanceInCents: item.read<int>('running_balance'),
            ),
          );
        }).toList(),
      );
}

final _transactionParties = StreamProvider.autoDispose<Map<String, String>>((
  ref,
) {
  final company = ref.watch(activeCompanyProvider);
  final db = ref.watch(appDatabaseProvider);
  final query = db.select(db.parties)
    ..where((p) => p.companyId.equals(company.id))
    ..orderBy([(p) => OrderingTerm.asc(p.name)]);
  return query.watch().map((rows) => {for (final p in rows) p.id: p.name});
});

Future<void> openLedgerTransaction(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onAddParty,
}) async {
  final companyId = ref.read(activeCompanyIdProvider);
  try {
    final parties = await ref.read(ledgerRepositoryProvider).getParties();
    if (!context.mounted || companyId != ref.read(activeCompanyIdProvider)) {
      return;
    }
    if (parties.isEmpty) {
      onAddParty();
      return;
    }
    final party = await showLedgerPartyPicker(context, parties);
    if (party != null &&
        context.mounted &&
        companyId == ref.read(activeCompanyIdProvider)) {
      _entrySheet(context, party);
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load parties. Please try again.'),
        ),
      );
    }
  }
}

Future<Party?> showLedgerPartyPicker(
  BuildContext context,
  List<Party> parties,
) {
  var search = '';
  return showModalBottomSheet<Party>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, update) {
        final matches = parties
            .where(
              (party) =>
                  party.name.toLowerCase().contains(search) ||
                  party.phoneNumber.contains(search),
            )
            .toList();
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              children: [
                const ListTile(title: Text('Select a party')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AdaptiveThemeHelper.isIos(context)
                      ? CupertinoSearchTextField(
                          onChanged: (value) =>
                              update(() => search = value.trim().toLowerCase()),
                        )
                      : SearchBar(
                          hintText: 'Search parties',
                          onChanged: (value) =>
                              update(() => search = value.trim().toLowerCase()),
                        ),
                ),
                Expanded(
                  child: matches.isEmpty
                      ? Center(
                          child: Text(
                            parties.isEmpty
                                ? 'Add a party first'
                                : 'No matching parties',
                          ),
                        )
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (_, index) {
                            final party = matches[index];
                            return ListTile(
                              title: Text(party.name),
                              subtitle: Text(
                                party.type == PartyType.customer
                                    ? 'Customer'
                                    : 'Supplier',
                              ),
                              onTap: () => Navigator.pop(sheetContext, party),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _entrySheet(BuildContext context, Party party, [LedgerEntry? entry]) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddEntryBottomSheet(
      partyId: party.id,
      partyName: party.name,
      initialType:
          entry?.type ??
          (party.type == PartyType.customer ? EntryType.got : EntryType.gave),
      entryToEdit: entry,
    ),
  );
}

class LedgerPartyFilters extends ConsumerWidget {
  const LedgerPartyFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(selectedPartyTypeFilterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AdaptiveSegmentedControl<String>(
        groupValue: current?.name ?? 'all',
        children: const {
          'all': Text('All'),
          'customer': Text('Customers'),
          'supplier': Text('Suppliers'),
        },
        onValueChanged: (value) => ref
            .read(selectedPartyTypeFilterProvider.notifier)
            .setFilter(switch (value) {
              'customer' => PartyType.customer,
              'supplier' => PartyType.supplier,
              _ => null,
            }),
      ),
    );
  }
}

Future<void> showArchivedLedgerParties(
  BuildContext context,
  WidgetRef ref,
) async {
  final repo = ref.read(driftLedgerRepositoryProvider);
  final company = ref.read(activeCompanyProvider);
  try {
    final parties = await repo.getParties(archived: true);
    if (!context.mounted || ref.read(activeCompanyProvider).id != company.id) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Column(
          children: [
            Text(
              'Archived parties',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            Expanded(
              child: parties.isEmpty
                  ? const Center(child: Text('No archived parties'))
                  : ListView.builder(
                      itemCount: parties.length,
                      itemBuilder: (context, index) {
                        final party = parties[index];
                        return ListTile(
                          title: Text(party.name),
                          subtitle: Text(party.type.name),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                await repo.restoreParty(party.id);
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              } catch (_) {
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(
                                    sheetContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not restore the party.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Restore'),
                          ),
                          onTap: () => showModalBottomSheet<void>(
                            context: sheetContext,
                            useSafeArea: true,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => FractionallySizedBox(
                              heightFactor: 0.8,
                              child: FutureBuilder<List<LedgerEntry>>(
                                future: repo.getEntriesForParty(party.id),
                                builder: (_, snapshot) {
                                  if (snapshot.hasError) {
                                    return const Center(
                                      child: Text(
                                        'Could not load transactions.',
                                      ),
                                    );
                                  }
                                  final entries = snapshot.data?.reversed
                                      .toList();
                                  if (entries == null) return const _Loading();
                                  if (entries.isEmpty) {
                                    return const Center(
                                      child: Text('No transactions yet'),
                                    );
                                  }
                                  return ListView.builder(
                                    itemCount: entries.length,
                                    itemBuilder: (_, i) => _TransactionTile(
                                      party: party,
                                      entry: entries[i],
                                      archived: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load archived parties.')),
      );
    }
  }
}

class LedgerHomeView extends ConsumerWidget {
  const LedgerHomeView({
    super.key,
    required this.onAddParty,
    required this.onAddTransaction,
    required this.onViewTransactions,
  });

  final VoidCallback onAddParty;
  final VoidCallback onAddTransaction;
  final VoidCallback onViewTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;
    final company = ref.watch(activeCompanyProvider);
    final summary = ref.watch(businessSummaryProvider);
    final activity = ref.watch(ledgerActivityProvider);
    return RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(ledgerActivityProvider);
        ref.invalidate(businessSummaryProvider);
        await ref.read(businessSummaryProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text('Outstanding balances', style: typography.titleLarge),
          const SizedBox(height: 12),
          summary.when(
            data: (value) => LiquidGlassCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _Balance(
                      label: 'To receive',
                      cents: value.$1,
                      currency: company.currencyCode,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Balance(
                      label: 'To pay',
                      cents: value.$2,
                      currency: company.currencyCode,
                      color: scheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const _Loading(),
            error: (_, _) =>
                _Retry(onRetry: () => ref.invalidate(businessSummaryProvider)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onAddTransaction,
                icon: const Icon(Icons.add),
                label: const Text('Add transaction'),
              ),
              OutlinedButton.icon(
                onPressed: onAddParty,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add party'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent transactions',
                  style: typography.titleLarge,
                ),
              ),
              TextButton(
                onPressed: onViewTransactions,
                child: const Text('View all'),
              ),
            ],
          ),
          activity.when(
            data: (rows) {
              final recent = rows;
              return recent.isEmpty
                  ? const ListTile(
                      title: Text('No transactions yet'),
                      subtitle: Text('Record a transaction to see it here.'),
                    )
                  : Column(
                      children: [
                        for (final row in recent)
                          _TransactionTile(
                            party: row.party,
                            entry: row.entry,
                            archived: row.archived,
                          ),
                      ],
                    );
            },
            loading: () => const _Loading(),
            error: (_, _) =>
                _Retry(onRetry: () => ref.invalidate(ledgerActivityProvider)),
          ),
        ],
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({
    required this.label,
    required this.cents,
    required this.currency,
    required this.color,
  });
  final String label, currency;
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          CurrencyFormatter.format(cents, currencyCode: currency),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class LedgerTransactionsView extends ConsumerStatefulWidget {
  const LedgerTransactionsView({super.key});
  @override
  ConsumerState<LedgerTransactionsView> createState() =>
      _LedgerTransactionsViewState();
}

class _LedgerTransactionsViewState
    extends ConsumerState<LedgerTransactionsView> {
  static const _pageSize = 50;
  int _limit = _pageSize;
  String _query = '';
  String? _partyId;
  EntryType? _type;
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final parties =
        ref.watch(_transactionParties).value ?? const <String, String>{};
    final activeParty = parties.containsKey(_partyId) ? _partyId : null;
    final companyId = ref.watch(activeCompanyIdProvider);
    final end = _range?.end;
    final page = ledgerActivityPageProvider((
      limit: _limit + 1,
      includeVoids: true,
      partyId: activeParty,
      type: _type,
      start: _range?.start,
      end: end == null ? null : DateTime(end.year, end.month, end.day + 1),
      search: _query,
    ));
    final activity = ref.watch(page);
    return activity.when(
      loading: () => const _Loading(),
      error: (_, _) => _Retry(onRetry: () => ref.invalidate(page)),
      data: (rows) {
        final filtered = rows.take(_limit).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: AdaptiveThemeHelper.isIos(context)
                  ? CupertinoSearchTextField(onChanged: _search)
                  : SearchBar(
                      hintText: 'Search transactions',
                      leading: const Icon(Icons.search),
                      onChanged: _search,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: activeParty ?? '',
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All parties'),
                      ),
                      for (final party in parties.entries)
                        DropdownMenuItem(
                          value: party.key,
                          child: Text(
                            party.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _partyId = value;
                      _limit = _pageSize;
                    }),
                  ),
                  DropdownButton<String>(
                    value: _type?.name ?? '',
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All types')),
                      DropdownMenuItem(value: 'gave', child: Text('You gave')),
                      DropdownMenuItem(value: 'got', child: Text('You got')),
                    ],
                    onChanged: (value) => setState(
                      () => _type = switch (value) {
                        'gave' => EntryType.gave,
                        'got' => EntryType.got,
                        _ => null,
                      },
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      _range == null
                          ? 'Dates'
                          : '${DateFormatter.formatShortDate(_range!.start)} – ${DateFormatter.formatShortDate(_range!.end)}',
                    ),
                    onPressed: _pickDates,
                  ),
                  if (_range != null)
                    IconButton(
                      tooltip: 'Clear dates',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _range = null),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        activeParty == null &&
                                _type == null &&
                                _range == null &&
                                _query.isEmpty
                            ? 'No transactions yet'
                            : 'No matching transactions',
                      ),
                    )
                  : ListView.separated(
                      key: PageStorageKey((
                        companyId,
                        activeParty,
                        _type,
                        _range,
                        _query,
                      )),
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount:
                          filtered.length + (rows.length > _limit ? 1 : 0),
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (_, index) => index == filtered.length
                          ? TextButton(
                              onPressed: () =>
                                  setState(() => _limit += _pageSize),
                              child: const Text('Load more'),
                            )
                          : _TransactionTile(
                              party: filtered[index].party,
                              entry: filtered[index].entry,
                              archived: filtered[index].archived,
                            ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _search(String value) => setState(() {
    _query = value.trim().toLowerCase();
    _limit = _pageSize;
  });

  Future<void> _pickDates() async {
    final range = await pickLedgerDates(context, initial: _range);
    if (mounted && range != null) {
      setState(() {
        _range = range;
        _limit = _pageSize;
      });
    }
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.party,
    required this.entry,
    required this.archived,
  });
  final Party party;
  final LedgerEntry entry;
  final bool archived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(activeCompanyProvider).currencyCode;
    final gave = entry.type == EntryType.gave;
    final direction = gave ? 'You gave' : 'You got';
    return ListTile(
      leading: CircleAvatar(
        child: Icon(gave ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
      ),
      title: Text(party.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.isVoided ? 'Voided · ' : ''}$direction · ${DateFormatter.formatShortDate(entry.date)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        CurrencyFormatter.format(entry.amountInCents, currencyCode: currency),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          decoration: entry.isVoided ? TextDecoration.lineThrough : null,
        ),
      ),
      onTap: () {
        showTransactionDetailSheet(
          context: context,
          entry: entry,
          party: party,
          readOnly: archived || entry.id.startsWith('open_'),
          editable: !entry.id.startsWith('vch_entry_'),
          currencyCode: currency,
          onEditEntry: () => _entrySheet(context, party, entry),
          onVoidEntry: () => _void(context, ref),
          onShowReceipt: showReceiptImageDialog,
        );
      },
    );
  }

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Void transaction?',
      message:
          'The transaction will be excluded from balances and kept in the audit history.',
      confirmLabel: 'Void transaction',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(ledgerActionControllerProvider)
          .deleteEntry(entry.id, party.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not void the transaction. Please try again.'),
          ),
        );
      }
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator.adaptive()),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Could not load data. Retry'),
    ),
  );
}
