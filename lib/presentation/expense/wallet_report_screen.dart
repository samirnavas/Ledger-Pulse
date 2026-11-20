import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/adaptive_surface_card.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../data/models/account_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'transaction_details_screen.dart';

final _walletBalanceProvider = StreamProvider.autoDispose
    .family<AccountModel?, String>((ref, id) {
      return ref.watch(expenseRepositoryProvider).watchWallet(id);
    });

final _walletTransactionsProvider = StreamProvider.autoDispose
    .family<List<VoucherModel>, String>((ref, id) {
      return ref
          .watch(expenseRepositoryProvider)
          .watchTransactions(walletIds: [id]);
    });

class WalletReportScreen extends ConsumerWidget {
  const WalletReportScreen({super.key, required this.wallet});

  final AccountModel wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider).value ?? const <AccountModel>[];
    final walletState = ref.watch(_walletBalanceProvider(wallet.id));
    final currentWallet = walletState.value;
    final categories =
        ref.watch(categoriesProvider).value ?? const <AccountModel>[];
    final names = {
      for (final account in [...wallets, ...categories])
        account.id: account.name,
    };
    final currency = ref.watch(activeCompanyProvider).currencyCode;
    final transactions = ref.watch(_walletTransactionsProvider(wallet.id));
    final isIos = AdaptiveThemeHelper.isIos(context);

    return AdaptiveScaffold(
      title: currentWallet?.name ?? wallet.name,
      body: Material(
        type: MaterialType.transparency,
        child: walletState.hasValue && currentWallet == null
            ? const Center(child: Text('Wallet unavailable'))
            : transactions.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator.adaptive()),
                error: (_, _) => const Center(
                  child: Text('Could not load wallet transactions'),
                ),
                data: (items) => ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: items.isEmpty ? 2 : items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final spent = items
                          .where((item) => item.type == VoucherType.expense)
                          .fold(
                            0,
                            (sum, item) => sum + item.totalAmountInCents,
                          );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _WalletSummary(
                            wallet: currentWallet ?? wallet,
                            spent: spent,
                            currency: currency,
                          ),
                          const AdaptiveSectionHeader(
                            title: 'All Transactions',
                          ),
                        ],
                      );
                    }
                    if (items.isEmpty) {
                      return EmptyStateView(
                        title: 'No wallet transactions',
                        subtitle:
                            'Transactions using this wallet will appear here.',
                        fallbackIcon: isIos
                            ? CupertinoIcons.list_bullet
                            : Icons.receipt_long_outlined,
                        animationSize: 72,
                      );
                    }
                    final item = items[index - 1];
                    final isTransfer = item.type == VoucherType.transfer;
                    final incoming = isTransfer
                        ? item.toWalletAccountId == wallet.id
                        : item.type == VoucherType.income;
                    final String typeLabel;
                    if (isTransfer) {
                      final otherId = incoming
                          ? item.walletAccountId
                          : item.toWalletAccountId;
                      final otherWallet = names[otherId] ?? 'wallet';
                      typeLabel = incoming
                          ? 'From $otherWallet'
                          : 'To $otherWallet';
                    } else {
                      typeLabel =
                          names[item.categoryAccountId] ??
                          (incoming ? 'Income' : 'Expense');
                    }
                    final note = item.narration?.trim() ?? '';
                    return AdaptiveListRow(
                      key: ValueKey('wallet_transaction_${item.id}'),
                      title: note.isEmpty ? typeLabel : note,
                      subtitle: [
                        if (note.isNotEmpty) typeLabel,
                        DateFormatter.formatFull(item.date),
                      ].join(' · '),
                      trailing: AmountText(
                        amountInCents: incoming
                            ? item.totalAmountInCents
                            : -item.totalAmountInCents,
                        currencyCode: currency,
                        showSign: true,
                        variant: AmountVariant.small,
                        overrideColor: Theme.of(context).colorScheme.onSurface,
                      ),
                      showDivider: index < items.length,
                      onTap: () =>
                          TransactionDetailsScreen.show(context, item, ref),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _WalletSummary extends StatelessWidget {
  const _WalletSummary({
    required this.wallet,
    required this.spent,
    required this.currency,
  });

  final AccountModel wallet;
  final int spent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isIos = AdaptiveThemeHelper.isIos(context);
    final foreground = isIos
        ? CupertinoColors.label.resolveFrom(context)
        : scheme.onPrimaryContainer;
    final isLiability = wallet.type == AccountType.liability;
    final balance = wallet.currentBalanceInCents;
    return AdaptiveSurfaceCard(
      padding: const EdgeInsets.all(20),
      color: isIos ? null : scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLiability
                ? (balance < 0 ? 'Credit balance' : 'Amount owed')
                : 'Remaining balance',
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
          ),
          const SizedBox(height: 4),
          AmountText(
            amountInCents: isLiability ? balance.abs() : balance,
            currencyCode: currency,
            variant: AmountVariant.large,
            overrideColor: foreground,
          ),
          const SizedBox(height: 16),
          Text(
            'Total spent',
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
          ),
          const SizedBox(height: 4),
          AmountText(
            amountInCents: spent,
            currencyCode: currency,
            overrideColor: foreground,
          ),
        ],
      ),
    );
  }
}
