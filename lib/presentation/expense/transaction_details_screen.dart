import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'quick_add_transaction_sheet.dart';
import 'widgets/category_icons.dart';

enum _TransactionAction { edit, delete }

class TransactionDetailsScreen extends ConsumerWidget {
  final VoucherModel transaction;

  const TransactionDetailsScreen({super.key, required this.transaction});

  static Future<void> show(
    BuildContext context,
    VoucherModel transaction,
    WidgetRef ref,
  ) async {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);
    final theme = Theme.of(context);
    final action = await showModalBottomSheet<_TransactionAction>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: isIos
          ? (theme.brightness == Brightness.dark
                ? CupertinoColors.systemBackground.darkColor
                : CupertinoColors.systemGroupedBackground)
          : theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => TransactionDetailsScreen(transaction: transaction),
    );
    if (!context.mounted) return;
    switch (action) {
      case _TransactionAction.edit:
        await QuickAddTransactionSheet.show(
          context,
          initialVoucher: transaction,
        );
      case _TransactionAction.delete:
        await confirmVoidExpenseTransaction(context, ref, transaction);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = theme.brightness == Brightness.dark;
    final categories = ref.watch(categoriesProvider).asData?.value;
    final wallets = ref.watch(walletsProvider).asData?.value;
    final company = ref.watch(activeCompanyProvider);
    if (company.id != transaction.companyId) {
      return const Center(
        child: Text('Transaction unavailable in this workspace'),
      );
    }
    final category = categories
        ?.where((c) => c.id == transaction.categoryAccountId)
        .firstOrNull;
    final wallet = wallets
        ?.where((w) => w.id == transaction.walletAccountId)
        .firstOrNull;
    final destination = wallets
        ?.where((w) => w.id == transaction.toWalletAccountId)
        .firstOrNull;
    final transfer = transaction.type == VoucherType.transfer;
    final voided = transaction.status == VoucherStatus.voided;
    final receipt = transaction.receiptPhotoUrl?.trim();
    final hasReceipt = receipt != null && receipt.isNotEmpty;
    final (typeColor, typeIcon) = switch (transaction.type) {
      VoucherType.income => (
        AppColors.income(context),
        Icons.arrow_downward_rounded,
      ),
      VoucherType.transfer => (
        AppColors.transfer(context),
        Icons.swap_horiz_rounded,
      ),
      _ => (AppColors.expense(context), Icons.arrow_upward_rounded),
    };
    final rowStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
    );

    Widget detail(String label, String value, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: rowStyle?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: rowStyle),
          ),
        ],
      ),
    );

    final summary = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isIos
            ? (isDark
                  ? CupertinoColors.systemGrey6.darkColor
                  : CupertinoColors.white)
            : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 14, color: typeColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          transaction.type.displayName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  transaction.status.displayName,
                  textAlign: TextAlign.end,
                  style: rowStyle?.copyWith(
                    color: voided
                        ? AppColors.payableRed
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AmountText(
              amountInCents: transaction.totalAmountInCents,
              currencyCode: company.currencyCode,
              variant: AmountVariant.large,
              overrideColor: typeColor,
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 0.5, color: colors.outlineVariant),
          detail(
            'Date & Time',
            DateFormat.yMMMd().add_jm().format(transaction.date.toLocal()),
            Icons.access_time_rounded,
          ),
          if (!transfer)
            detail(
              'Category',
              category?.name ?? 'Uncategorized',
              categoryIcon(category),
            ),
          detail(
            transfer ? 'From wallet' : 'Wallet',
            wallet?.name ?? 'Unavailable',
            Icons.account_balance_wallet_outlined,
          ),
          if (transfer)
            detail(
              'To wallet',
              destination?.name ?? 'Unavailable',
              Icons.account_balance_wallet_outlined,
            ),
          if (transaction.referenceNumber?.trim().isNotEmpty ?? false)
            detail(
              'Reference',
              transaction.referenceNumber!,
              Icons.tag_rounded,
            ),
          if (transaction.narration?.trim().isNotEmpty ?? false)
            detail('Note', transaction.narration!, Icons.notes_rounded),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: hasReceipt ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ModalDragHandle(margin: EdgeInsets.only(bottom: 12)),
            Row(
              children: [
                Icon(
                  isIos ? CupertinoIcons.doc_text : Icons.receipt_long_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Transaction Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              fit: hasReceipt ? FlexFit.tight : FlexFit.loose,
              child: CustomScrollView(
                shrinkWrap: !hasReceipt,
                slivers: [
                  SliverToBoxAdapter(child: summary),
                  if (hasReceipt)
                    SliverLayoutBuilder(
                      builder: (context, constraints) => SliverToBoxAdapter(
                        child: SizedBox(
                          height: math.max(
                            260.0,
                            constraints.viewportMainAxisExtent -
                                constraints.precedingScrollExtent,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Invoice / receipt',
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Container(
                                    key: const Key(
                                      'transaction_invoice_section',
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainer,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InteractiveViewer(
                                      maxScale: 5,
                                      child: _InvoiceImage(source: receipt),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!voided) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_TransactionAction.edit),
                      icon: Icon(
                        isIos ? CupertinoIcons.pencil : Icons.edit_outlined,
                        size: 18,
                      ),
                      label: const Text('Edit details'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          Navigator.of(context).pop(_TransactionAction.delete),
                      icon: Icon(
                        isIos
                            ? CupertinoIcons.trash
                            : Icons.delete_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Delete'),
                      style: FilledButton.styleFrom(
                        foregroundColor: AppColors.payableRed,
                        backgroundColor: AppColors.payableRed.withValues(
                          alpha: isDark ? 0.2 : 0.12,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Confirms and voids an expense transaction from either the voucher or a swipe.
Future<bool> confirmVoidExpenseTransaction(
  BuildContext context,
  WidgetRef ref,
  VoucherModel transaction,
) async {
  final workspace = ref.read(activeCompanyProvider);
  if (workspace.id != transaction.companyId) return false;
  final type = switch (transaction.type) {
    VoucherType.expense => 'expense',
    VoucherType.income => 'income entry',
    VoucherType.transfer => 'transfer',
    _ => 'transaction',
  };
  final amount = CurrencyFormatter.format(
    transaction.totalAmountInCents,
    currencyCode: workspace.currencyCode,
    absolute: true,
    showDecimalsAlways: false,
  );
  final date = DateFormat.yMMMd().format(transaction.date.toLocal());
  final label = '$amount $type';
  final confirmed = await showAdaptiveConfirmDialog(
    context: context,
    title: 'Delete transaction?',
    message:
        'Delete this $label from $date? This will reverse its effect on your wallet balances.',
    confirmLabel: 'Delete',
    isDestructive: true,
  );
  if (!confirmed ||
      !context.mounted ||
      ref.read(activeCompanyProvider).id != workspace.id) {
    return false;
  }
  try {
    await ref.read(expenseRepositoryProvider).voidTransaction(transaction.id);
    if (context.mounted) {
      showAppFeedback(context, '$label deleted');
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      showAppFeedback(
        context,
        'Error voiding transaction: $error',
        isError: true,
      );
    }
    return false;
  }
}

class _InvoiceImage extends StatelessWidget {
  final String source;

  const _InvoiceImage({required this.source});

  @override
  Widget build(BuildContext context) {
    Widget unavailable(BuildContext context, Object error, StackTrace? stack) =>
        const Center(child: Text('Invoice unavailable on this device'));
    final uri = Uri.tryParse(source);
    if (uri?.scheme == 'https' || uri?.scheme == 'http') {
      return Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: unavailable,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
      );
    }
    return Image.file(
      uri?.scheme == 'file' ? File.fromUri(uri!) : File(source),
      fit: BoxFit.contain,
      errorBuilder: unavailable,
    );
  }
}
