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
import '../../data/local/ledger_entry_balance.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import 'add_entry_bottom_sheet.dart';
import 'widgets/party_transaction_voucher_sheet.dart';

final ledgerActivityProvider =
    StreamProvider.autoDispose<
      List<({Party party, LedgerEntry entry, bool archived})>
    >((ref) {
      final company = ref.watch(activeCompanyProvider);
      if (!company.isLedger) return Stream.value(const []);
      final db = ref.watch(appDatabaseProvider);
      final entries = db.ledgerEntries;
      final parties = db.parties;
      final query =
          db.select(entries).join([
              innerJoin(parties, parties.id.equalsExp(entries.partyId)),
            ])
            ..where(
              entries.companyId.equals(company.id) &
                  parties.companyId.equals(company.id),
            )
            ..orderBy([
              OrderingTerm.asc(entries.date),
              OrderingTerm.asc(entries.createdAt),
              OrderingTerm.asc(entries.id),
            ]);

      return query.watch().map((result) {
        final rows = result.map((item) => item.readTable(entries)).toList();
        final balances = LedgerEntryBalance(rows);
        final running = <String, int>{};
        final history = <({Party party, LedgerEntry entry, bool archived})>[];
        for (final item in result) {
          final row = item.readTable(entries);
          if (row.isDeleted || balances.isLegacyOffset(row)) continue;
          final p = item.readTable(parties);
          final runningBalance = (running[p.id] ?? 0) + balances.delta(row);
          running[p.id] = runningBalance;
          history.add((
            archived: p.isDeleted,
            party: Party(
              id: p.id,
              name: p.name,
              phoneNumber: p.phoneNumber,
              type: p.type,
              netBalanceInCents: p.netBalanceInCents,
              lastUpdated: p.lastUpdated,
            ),
            entry: LedgerEntry(
              id: row.id,
              partyId: row.partyId,
              type: row.type,
              amountInCents: row.amountInCents,
              date: row.date,
              note: row.note,
              receiptPhotoUrl: row.receiptPhotoUrl,
              isVoided: row.isVoided,
              runningBalanceInCents: runningBalance,
            ),
          ));
        }
        return history.reversed.toList();
      });
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
              final recent = rows.where((row) => !row.entry.isVoided).take(5);
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
  String _query = '';
  String? _partyId;
  EntryType? _type;
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(ledgerActivityProvider);
    return activity.when(
      loading: () => const _Loading(),
      error: (_, _) =>
          _Retry(onRetry: () => ref.invalidate(ledgerActivityProvider)),
      data: (rows) {
        final parties = {for (final row in rows) row.party.id: row.party.name};
        final activeParty = parties.containsKey(_partyId) ? _partyId : null;
        final filtered = rows.where((row) {
          final day = DateUtils.dateOnly(row.entry.date.toLocal());
          return (activeParty == null || row.party.id == activeParty) &&
              (_type == null || row.entry.type == _type) &&
              (_range == null ||
                  (!day.isBefore(_range!.start) &&
                      !day.isAfter(_range!.end))) &&
              (row.party.name.toLowerCase().contains(_query) ||
                  (row.entry.note ?? '').toLowerCase().contains(_query));
        }).toList();
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
                    onChanged: (value) => setState(() => _partyId = value),
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
                        rows.isEmpty
                            ? 'No transactions yet'
                            : 'No matching transactions',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 64),
                      itemBuilder: (_, index) => _TransactionTile(
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

  void _search(String value) =>
      setState(() => _query = value.trim().toLowerCase());

  Future<void> _pickDates() async {
    final range = await pickLedgerDates(context, initial: _range);
    if (mounted && range != null) setState(() => _range = range);
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
