import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/amount_text.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'widgets/wallet_overview.dart';

class WalletTransferScreen extends ConsumerStatefulWidget {
  const WalletTransferScreen({
    super.key,
    required this.workspace,
    required this.hideBalances,
  });

  final Company workspace;
  final bool hideBalances;

  @override
  ConsumerState<WalletTransferScreen> createState() =>
      _WalletTransferScreenState();
}

class _WalletTransferScreenState extends ConsumerState<WalletTransferScreen> {
  final _amount = TextEditingController();
  String? _fromId;
  String? _toId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(AccountModel from, AccountModel to, int cents) async {
    if (_saving || ref.read(activeCompanyProvider).id != widget.workspace.id)
      return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(expenseRepositoryProvider)
          .addTransfer(
            walletAccountId: from.id,
            toWalletAccountId: to.id,
            amountInCents: cents,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Could not save the transfer. Check both wallets and try again.';
      });
    }
  }

  Widget _walletPicker(
    String label,
    AccountModel? selected,
    List<AccountModel> wallets,
    ValueChanged<String?>? onChange,
  ) {
    final currency = widget.workspace.currencyCode;
    final balance = selected?.currentBalanceInCents ?? 0;
    final liability = selected?.type == AccountType.liability;
    final balanceLabel = liability
        ? (balance < 0 ? 'Card credit' : 'Amount owed')
        : 'Current balance';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveDropdownField<String>(
          label: label,
          value: selected?.id,
          onChanged: onChange,
          prefixIcon: selected == null
              ? null
              : Icon(WalletKind.of(selected).icon(context)),
          items: [
            for (final wallet in wallets)
              AdaptivePickerItem(
                value: wallet.id,
                label: wallet.name,
                icon: Icon(WalletKind.of(wallet).icon(context)),
              ),
          ],
        ),
        if (selected != null && !widget.hideBalances)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '$balanceLabel ${CurrencyFormatter.format(liability ? balance.abs() : balance, currencyCode: currency)}',
            ),
          ),
      ],
    );
  }

  Widget _preview(AccountModel wallet, int movement, {required bool alignEnd}) {
    final balance = wallet.currentBalanceInCents;
    final liability = wallet.type == AccountType.liability;
    final after = balance + (liability ? -movement : movement);
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          wallet.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        ),
        const SizedBox(height: 4),
        AmountText(
          amountInCents: liability ? after.abs() : after,
          currencyCode: widget.workspace.currencyCode,
          overrideColor: Theme.of(context).colorScheme.onSurface,
        ),
        if (liability) Text(after < 0 ? 'Credit' : 'Owed'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaceMatches =
        ref.watch(activeCompanyProvider.select((workspace) => workspace.id)) ==
        widget.workspace.id;
    final isIos = AdaptiveThemeHelper.isIos(context);
    final theme = Theme.of(context);
    final currency = widget.workspace.currencyCode;
    final input = _amount.text.trim();
    final cents = RegExp(r'^(\d{1,9}(\.\d{0,2})?|\.\d{1,2})$').hasMatch(input)
        ? CurrencyFormatter.parseToCents(input)
        : 0;
    final validAmount = cents > 0;

    return PopScope(
      canPop:
          !_saving && _amount.text.isEmpty && _fromId == null && _toId == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final discard = await showAdaptiveConfirmDialog(
          context: context,
          title: 'Discard transfer?',
          message: 'Your unfinished transfer will be lost.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep editing',
          isDestructive: true,
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: AdaptiveScaffold(
        title: 'Transfer money',
        body: !workspaceMatches
            ? const Center(
                child: Text('Return to the original workspace to continue.'),
              )
            : ref
                  .watch(walletsProvider)
                  .when(
                    loading: () => const Center(
                      child: CircularProgressIndicator.adaptive(),
                    ),
                    error: (_, _) =>
                        const Center(child: Text('Could not load wallets.')),
                    data: (wallets) {
                      if (wallets.length < 2)
                        return const Center(
                          child: Text('Two active wallets are required.'),
                        );
                      final byId = {
                        for (final wallet in wallets) wallet.id: wallet,
                      };
                      final from = byId[_fromId];
                      final to = byId[_toId];
                      final canTransfer =
                          from != null &&
                          to != null &&
                          from.id != to.id &&
                          validAmount;
                      final amountField = isIos
                          ? CupertinoTextField(
                              key: const Key('wallet_transfer_amount'),
                              controller: _amount,
                              enabled: !_saving,
                              placeholder: 'Amount',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() => _error = null),
                            )
                          : TextField(
                              key: const Key('wallet_transfer_amount'),
                              controller: _amount,
                              enabled: !_saving,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Amount',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() => _error = null),
                            );
                      return ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        children: [
                          Center(
                            child: Text(
                              widget.workspace.name,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Transfer amount',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          Center(
                            child: AmountText(
                              amountInCents: cents,
                              currencyCode: currency,
                              variant: AmountVariant.large,
                              overrideColor: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          amountField,
                          if (_amount.text.isNotEmpty && !validAmount)
                            Text(
                              'Enter a positive amount with up to two decimal places.',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          const SizedBox(height: 20),
                          IgnorePointer(
                            ignoring: _saving,
                            child: _walletPicker(
                              'From wallet',
                              from,
                              wallets
                                  .where((wallet) => wallet.id != _toId)
                                  .toList(),
                              (value) => setState(() => _fromId = value),
                            ),
                          ),
                          Center(
                            child: _SwapWalletsButton(
                              enabled: !_saving && (from != null || to != null),
                              onSwap: () => setState(() {
                                final from = _fromId;
                                _fromId = _toId;
                                _toId = from;
                              }),
                            ),
                          ),
                          IgnorePointer(
                            ignoring: _saving,
                            child: _walletPicker(
                              'To wallet',
                              to,
                              wallets
                                  .where((wallet) => wallet.id != _fromId)
                                  .toList(),
                              (value) => setState(() => _toId = value),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (canTransfer && !widget.hideBalances) ...[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Balance after transfer',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _preview(
                                            from,
                                            -cents,
                                            alignEnd: false,
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 16,
                                          ),
                                        ),
                                        Expanded(
                                          child: _preview(
                                            to,
                                            cents,
                                            alignEnd: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    const Text(
                                      'Total wallet balance stays the same.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Text(
                            'Wallet transfers are excluded from income and expenses.',
                          ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          const SizedBox(height: 16),
                          AdaptiveButton(
                            key: const Key('confirm_wallet_transfer'),
                            onPressed: canTransfer && !_saving
                                ? () => _save(from, to, cents)
                                : null,
                            isLoading: _saving,
                            child: const Text('Confirm transfer'),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}

class _SwapWalletsButton extends StatelessWidget {
  const _SwapWalletsButton({required this.enabled, required this.onSwap});
  final bool enabled;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    if (AdaptiveThemeHelper.isIos(context)) {
      return Tooltip(
        message: 'Swap wallets',
        child: CupertinoButton(
          onPressed: enabled ? onSwap : null,
          child: const Icon(CupertinoIcons.arrow_up_arrow_down),
        ),
      );
    }
    return IconButton(
      tooltip: 'Swap wallets',
      onPressed: enabled ? onSwap : null,
      icon: const Icon(Icons.swap_vert_rounded),
    );
  }
}
