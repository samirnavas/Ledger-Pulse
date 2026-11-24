import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/amount_text.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'transaction_details_screen.dart';
import 'widgets/category_icons.dart';

final _walletActivityProvider = StreamProvider.autoDispose<List<VoucherModel>>((
  ref,
) {
  return ref.watch(expenseRepositoryProvider).watchTransactions();
});

class WalletActivityScreen extends ConsumerStatefulWidget {
  const WalletActivityScreen({
    super.key,
    required this.workspace,
    required this.hideBalances,
  });

  final Company workspace;
  final bool hideBalances;

  @override
  ConsumerState<WalletActivityScreen> createState() =>
      _WalletActivityScreenState();
}

class _WalletActivityScreenState extends ConsumerState<WalletActivityScreen> {
  bool _transfersOnly = false;

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(activeCompanyProvider);
    return AdaptiveScaffold(
      title: 'Wallet activity',
      body: company.id == widget.workspace.id
          ? _buildActivity(context)
          : const Center(
              child: Text('Activity unavailable in this workspace.'),
            ),
    );
  }

  Widget _buildActivity(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final active = ref.watch(walletsProvider).asData?.value ?? [];
    final archived = ref.watch(archivedWalletsProvider).asData?.value ?? [];
    final names = {
      for (final wallet in [...active, ...archived]) wallet.id: wallet.name,
    };
    final categories = ref.watch(categoriesProvider).asData?.value ?? [];
    final byCategoryId = {
      for (final category in categories) category.id: category,
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: AdaptiveSegmentedControl<bool>(
            groupValue: _transfersOnly,
            children: const {
              false: Text('All activity'),
              true: Text('Transfers'),
            },
            onValueChanged: (value) => setState(() => _transfersOnly = value),
          ),
        ),
        Expanded(
          child: ref
              .watch(_walletActivityProvider)
              .when(
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (_, _) => const Center(
                  child: Text('Could not load wallet activity.'),
                ),
                data: (transactions) {
                  final entries = _transfersOnly
                      ? transactions
                            .where((item) => item.type == VoucherType.transfer)
                            .toList()
                      : transactions;
                  if (entries.isEmpty)
                    return Center(
                      child: Text(
                        _transfersOnly
                            ? 'No transfers yet.'
                            : 'No wallet activity yet.',
                      ),
                    );
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final isTransfer = entry.type == VoucherType.transfer;
                      final category = byCategoryId[entry.categoryAccountId];
                      final source = names[entry.walletAccountId] ?? 'Wallet';
                      final destination =
                          names[entry.toWalletAccountId] ?? 'Wallet';
                      final title = isTransfer
                          ? '$source → $destination'
                          : entry.narration?.trim();
                      final date = DateFormatter.formatFull(entry.date);
                      return AdaptiveListRow(
                        leading: Icon(
                          isTransfer
                              ? (isIos
                                    ? CupertinoIcons.arrow_right_arrow_left
                                    : Icons.swap_horiz_rounded)
                              : categoryIcon(category),
                        ),
                        title: title != null && title.isNotEmpty
                            ? title
                            : category?.name ?? entry.type.name,
                        subtitle: isTransfer ? date : '$source · $date',
                        trailing: widget.hideBalances
                            ? const Text(
                                '••••',
                                semanticsLabel: 'Amount hidden',
                              )
                            : AmountText(
                                amountInCents: entry.type == VoucherType.expense
                                    ? -entry.totalAmountInCents
                                    : entry.totalAmountInCents,
                                showSign: !isTransfer,
                                currencyCode: widget.workspace.currencyCode,
                                variant: AmountVariant.small,
                                overrideColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                        onTap: widget.hideBalances
                            ? null
                            : () => TransactionDetailsScreen.show(
                                context,
                                entry,
                                ref,
                              ),
                      );
                    },
                  );
                },
              ),
        ),
      ],
    );
  }
}
