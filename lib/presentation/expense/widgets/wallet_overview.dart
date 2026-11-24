import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/adaptive_theme.dart';
import '../../../core/widgets/adaptive_button.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../data/models/account_model.dart';

enum WalletKind {
  cash('Cash', Icons.payments_rounded, CupertinoIcons.money_dollar),
  bank('Bank', Icons.account_balance_rounded, CupertinoIcons.building_2_fill),
  other(
    'Other wallets',
    Icons.account_balance_wallet_rounded,
    CupertinoIcons.money_dollar_circle,
  ),
  credit('Credit card', Icons.credit_card_rounded, CupertinoIcons.creditcard);

  const WalletKind(this.label, this.materialIcon, this.iosIcon);

  final String label;
  final IconData materialIcon;
  final IconData iosIcon;

  static WalletKind of(AccountModel wallet) {
    if (wallet.type == AccountType.liability) return credit;
    final name = wallet.name.toLowerCase();
    if (name.contains('cash')) return cash;
    if (name.contains('bank')) return bank;
    return other;
  }

  IconData icon(BuildContext context) =>
      AdaptiveThemeHelper.isIos(context) ? iosIcon : materialIcon;

  Color color(BuildContext context) {
    if (AdaptiveThemeHelper.isIos(context)) {
      return switch (this) {
        cash => CupertinoColors.systemGreen,
        bank => CupertinoColors.systemBlue,
        other => CupertinoColors.systemIndigo,
        credit => CupertinoColors.systemRed,
      }.resolveFrom(context);
    }
    final colors = Theme.of(context).colorScheme;
    return switch (this) {
      cash => colors.primary,
      bank => colors.secondary,
      other => colors.tertiary,
      credit => colors.error,
    };
  }
}

class WalletOverview extends StatelessWidget {
  const WalletOverview({
    super.key,
    required this.wallets,
    required this.currency,
    required this.hideBalances,
    required this.onAdd,
    required this.onTransfer,
    required this.onActivity,
  });

  final List<AccountModel> wallets;
  final String currency;
  final bool hideBalances;
  final VoidCallback onAdd;
  final VoidCallback? onTransfer;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final colors = theme.colorScheme;
    final foreground = isIos
        ? CupertinoColors.label.resolveFrom(context)
        : colors.onSurface;
    final positiveWallets = <AccountModel>[];
    var assets = 0;
    var credit = 0;
    for (final wallet in wallets) {
      final balance = wallet.currentBalanceInCents;
      final kind = WalletKind.of(wallet);
      if (kind == WalletKind.credit) {
        credit += balance;
      } else {
        assets += balance;
        if (balance > 0) positiveWallets.add(wallet);
      }
    }
    positiveWallets.sort(
      (a, b) => b.currentBalanceInCents.compareTo(a.currentBalanceInCents),
    );
    final positiveHoldings = [
      for (final wallet in positiveWallets.take(3))
        (
          wallet.name,
          wallet.currentBalanceInCents,
          WalletKind.of(wallet).color(context),
        ),
      if (positiveWallets.length > 3)
        (
          'Other wallets',
          positiveWallets
              .skip(3)
              .fold(0, (total, wallet) => total + wallet.currentBalanceInCents),
          colors.outline,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: isIos
                ? CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                    context,
                  )
                : colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(isIos ? 20 : 28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total balance', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                if (hideBalances)
                  Text(
                    '••••',
                    semanticsLabel: 'Balance hidden',
                    style: theme.textTheme.headlineMedium,
                  )
                else
                  AmountText(
                    key: const Key('wallets_total_balance'),
                    amountInCents: assets - credit,
                    currencyCode: currency,
                    variant: AmountVariant.large,
                    overrideColor: foreground,
                    style: const TextStyle(fontSize: 34),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Active assets less credit card debt. Card credits increase the total. Archived wallets are excluded.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (!hideBalances && positiveHoldings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Where your money is held',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Positive balances in active asset wallets.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        spacing: 2,
                        children: [
                          for (final (_, balance, color) in positiveHoldings)
                            Expanded(
                              flex: balance,
                              child: ColoredBox(
                                color: color,
                                child: const SizedBox(height: 8),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      for (final (name, balance, color) in positiveHoldings)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: color),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                name,
                                style: theme.textTheme.labelSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            AmountText(
                              amountInCents: balance,
                              currencyCode: currency,
                              variant: AmountVariant.small,
                              overrideColor: foreground,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _action(
              'Add wallet',
              isIos ? CupertinoIcons.add : Icons.add_rounded,
              onAdd,
              primary: true,
            ),
            _action(
              'Transfer',
              isIos
                  ? CupertinoIcons.arrow_right_arrow_left
                  : Icons.swap_horiz_rounded,
              onTransfer,
            ),
            _action(
              'Activity',
              isIos ? CupertinoIcons.time : Icons.history_rounded,
              onActivity,
            ),
          ],
        ),
        if (wallets.length == 1)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Add another wallet to transfer money.'),
          ),
      ],
    );
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool primary = false,
  }) {
    return AdaptiveButton(
      onPressed: onPressed,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      type: primary ? AdaptiveButtonType.primary : AdaptiveButtonType.secondary,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      ),
    );
  }
}
