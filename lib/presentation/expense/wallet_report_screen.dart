import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_form_sheet.dart';
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
  const WalletReportScreen({
    super.key,
    required this.wallet,
    this.hideBalances = false,
  });

  final AccountModel wallet;
  final bool hideBalances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(activeCompanyProvider);
    if (workspace.id != wallet.companyId) {
      return const AdaptiveScaffold(
        title: 'Wallet report',
        body: Center(child: Text('Wallet unavailable in this workspace')),
      );
    }
    final wallets =
        ref.watch(walletsProvider).asData?.value ?? const <AccountModel>[];
    final archived =
        ref.watch(archivedWalletsProvider).asData?.value ??
        const <AccountModel>[];
    final walletState = ref.watch(_walletBalanceProvider(wallet.id));
    final currentWallet = walletState.asData?.value;
    final categories =
        ref.watch(categoriesProvider).asData?.value ?? const <AccountModel>[];
    final names = {
      for (final account in [...wallets, ...archived, ...categories])
        account.id: account.name,
    };
    final currency = workspace.currencyCode;
    final transactions = ref.watch(_walletTransactionsProvider(wallet.id));
    final isIos = AdaptiveThemeHelper.isIos(context);

    return AdaptiveScaffold(
      title: currentWallet?.name ?? wallet.name,
      body: Material(
        type: MaterialType.transparency,
        child: walletState.asData != null && currentWallet == null
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
                            hideBalances: hideBalances,
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
                      trailing: hideBalances
                          ? const Text('••••', semanticsLabel: 'Amount hidden')
                          : AmountText(
                              amountInCents: incoming
                                  ? item.totalAmountInCents
                                  : -item.totalAmountInCents,
                              currencyCode: currency,
                              showSign: true,
                              variant: AmountVariant.small,
                              overrideColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                      showDivider: index < items.length,
                      onTap: hideBalances
                          ? null
                          : () => TransactionDetailsScreen.show(
                              context,
                              item,
                              ref,
                            ),
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
    required this.hideBalances,
  });

  final AccountModel wallet;
  final int spent;
  final String currency;
  final bool hideBalances;

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
          if (hideBalances)
            const Text('••••', semanticsLabel: 'Balance hidden')
          else
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
          if (hideBalances)
            const Text('••••', semanticsLabel: 'Amount hidden')
          else
            AmountText(
              amountInCents: spent,
              currencyCode: currency,
              overrideColor: foreground,
            ),
          if (!hideBalances) ...[
            const SizedBox(height: 12),
            AdaptiveButton(
              type: AdaptiveButtonType.secondary,
              onPressed: () => _compareBalance(context),
              child: const Text('Check balance'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _compareBalance(BuildContext context) {
    return showAdaptiveFormSheet<void>(
      context: context,
      title: 'Check balance',
      doneLabel: 'Done',
      builder: (context) =>
          _WalletBalanceCheck(wallet: wallet, currency: currency),
    );
  }
}

class _WalletBalanceCheck extends ConsumerStatefulWidget {
  const _WalletBalanceCheck({required this.wallet, required this.currency});

  final AccountModel wallet;
  final String currency;

  @override
  ConsumerState<_WalletBalanceCheck> createState() =>
      _WalletBalanceCheckState();
}

class _WalletBalanceCheckState extends ConsumerState<_WalletBalanceCheck> {
  String _input = '';

  @override
  Widget build(BuildContext context) {
    if (ref.watch(activeCompanyProvider.select((company) => company.id)) !=
        widget.wallet.companyId) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('Wallet unavailable in this workspace.'),
      );
    }
    final wallet = ref
        .watch(_walletBalanceProvider(widget.wallet.id))
        .asData
        ?.value;
    final valid = RegExp(
      r'^-?(\d{1,12}(\.\d{0,2})?|\.\d{1,2})$',
    ).hasMatch(_input.trim());
    final difference = wallet == null || !valid
        ? null
        : CurrencyFormatter.parseToCents(_input) - wallet.currentBalanceInCents;
    final isCredit = widget.wallet.type == AccountType.liability;
    const keyboard = TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );
    final isIos = AdaptiveThemeHelper.isIos(context);
    final label = isCredit ? 'Statement amount owed' : 'Actual balance';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            wallet == null
                ? 'Loading recorded balance…'
                : 'Recorded balance ${CurrencyFormatter.format(wallet.currentBalanceInCents, currencyCode: widget.currency)}',
          ),
          const SizedBox(height: 8),
          Text(
            isCredit
                ? 'Enter the amount owed, or a negative amount if your card has a credit.'
                : 'Enter the current balance from your statement or count your cash.',
          ),
          const SizedBox(height: 12),
          if (isIos)
            CupertinoTextField(
              placeholder: label,
              keyboardType: keyboard,
              onChanged: (value) => setState(() => _input = value),
            )
          else
            TextField(
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              keyboardType: keyboard,
              onChanged: (value) => setState(() => _input = value),
            ),
          const SizedBox(height: 12),
          if (difference == 0)
            const Text('Your recorded balance matches.')
          else if (difference != null)
            Text(
              'Your actual balance is ${CurrencyFormatter.format(difference.abs(), currencyCode: widget.currency)} ${difference > 0 ? 'higher' : 'lower'} than recorded.',
            ),
          if (!valid && _input.isNotEmpty)
            const Text('Enter an amount with up to two decimal places.'),
        ],
      ),
    );
  }
}
