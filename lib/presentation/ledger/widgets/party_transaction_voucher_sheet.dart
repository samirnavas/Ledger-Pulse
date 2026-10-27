import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/draggable_modal_sheet.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/transaction_model.dart';

/// Modal bottom sheet showing detailed Transaction Voucher with Void / Edit actions.
void showTransactionDetailSheet({
  required BuildContext context,
  required LedgerEntry entry,
  required Party party,
  required VoidCallback onEditEntry,
  required VoidCallback onVoidEntry,
  required void Function(BuildContext, LedgerEntry) onShowReceipt,
}) {
  HapticFeedback.lightImpact();
  final isIos = AdaptiveThemeHelper.isIos(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final isGave = entry.type == EntryType.gave;
  final color = isGave ? AppColors.payableRed : AppColors.receivableGreen;

  showModalBottomSheet(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isIos
        ? (isDark
            ? CupertinoColors.systemBackground.darkColor
            : CupertinoColors.systemGroupedBackground)
        : Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ModalDragHandle(
                margin: EdgeInsets.only(bottom: 12.0),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    isIos ? CupertinoIcons.doc_text : Icons.receipt_long_rounded,
                    size: 20,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Transaction Voucher',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Voucher Summary Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isIos
                      ? (isDark ? CupertinoColors.systemGrey6 : CupertinoColors.white)
                      : Theme.of(sheetContext).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: isDark ? 0.3 : 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isGave
                                    ? (isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded)
                                    : (isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded),
                                size: 14,
                                color: color,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isGave ? 'YOU GAVE' : 'YOU GOT',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (entry.isVoided)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.payableRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.payableRed.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'VOIDED',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.payableRed,
                                letterSpacing: 0.5,
                              ),
                            ),
                          )
                        else
                          Text(
                            DateFormatter.formatRelative(entry.date),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${isGave ? "-" : "+"} ${CurrencyFormatter.format(entry.amountInCents)}',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: entry.isVoided ? color.withValues(alpha: 0.45) : color,
                        decoration: entry.isVoided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 14),
                    _buildVoucherRow(
                      context: sheetContext,
                      label: 'Party',
                      value: '${party.name} (${party.phoneNumber})',
                      icon: isIos ? CupertinoIcons.person : Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildVoucherRow(
                      context: sheetContext,
                      label: 'Date & Time',
                      value: DateFormatter.formatFull(entry.date),
                      icon: isIos ? CupertinoIcons.time : Icons.access_time_rounded,
                    ),
                    const SizedBox(height: 10),
                    _buildVoucherRow(
                      context: sheetContext,
                      label: 'Note',
                      value: entry.note != null && entry.note!.trim().isNotEmpty
                          ? entry.note!
                          : 'No note provided',
                      icon: isIos ? CupertinoIcons.doc_text : Icons.notes_rounded,
                    ),
                    if (entry.runningBalanceInCents != null) ...[
                      const SizedBox(height: 10),
                      _buildVoucherRow(
                        context: sheetContext,
                        label: 'Running Balance',
                        value: CurrencyFormatter.format(entry.runningBalanceInCents!),
                        icon: isIos
                            ? CupertinoIcons.money_dollar_circle
                            : Icons.account_balance_wallet_outlined,
                      ),
                    ],
                    if (entry.receiptPhotoUrl != null) ...[
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onShowReceipt(context, entry);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(sheetContext).colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(sheetContext).colorScheme.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isIos ? CupertinoIcons.doc_text : Icons.receipt_long_rounded,
                                size: 20,
                                color: Theme.of(sheetContext).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Attached Bill Receipt',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(sheetContext).colorScheme.primary,
                                      ),
                                    ),
                                    Text(
                                      'Tap to view receipt image preview',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                isIos ? CupertinoIcons.chevron_right : Icons.chevron_right_rounded,
                                size: 18,
                                color: Theme.of(sheetContext).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Action Buttons
              if (!entry.isVoided)
                Row(
                  children: [
                    // Edit Note / Details button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          onEditEntry();
                        },
                        icon: Icon(
                          isIos ? CupertinoIcons.pencil : Icons.edit_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Edit Note / Details',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Delete / Void Entry button
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          onVoidEntry();
                        },
                        icon: Icon(
                          isIos ? CupertinoIcons.trash : Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.payableRed,
                        ),
                        label: const Text(
                          'Delete / Void Entry',
                          style: TextStyle(
                            color: AppColors.payableRed,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.payableRed.withValues(
                            alpha: isDark ? 0.2 : 0.12,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.payableRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.payableRed.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.info_circle : Icons.info_outline_rounded,
                        size: 16,
                        color: AppColors.payableRed,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'This transaction is voided and archived.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.payableRed,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildVoucherRow({
  required BuildContext context,
  required String label,
  required String value,
  required IconData icon,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Text(
        '$label: ',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}

/// Displays the receipt photo in a draggable modal dialog.
void showReceiptImageDialog(BuildContext context, LedgerEntry entry) {
  HapticFeedback.lightImpact();

  showAdaptiveDraggableModal(
    context: context,
    initialChildSize: 0.65,
    minChildSize: 0.3,
    maxChildSize: 0.92,
    snapSizes: const [0.65, 0.92],
    builder: (context, scrollController) {
      return SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bill / Receipt',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: entry.receiptPhotoUrl!.startsWith('http')
                  ? Image.network(
                      entry.receiptPhotoUrl!,
                      height: 280,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => Container(
                        height: 180,
                        color: AppColors.surfaceCardM3,
                        child: const Center(
                          child: Text('Receipt Preview (Offline Mock)'),
                        ),
                      ),
                    )
                  : Image.file(
                      File(entry.receiptPhotoUrl!),
                      height: 280,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => Container(
                        height: 180,
                        color: AppColors.surfaceCardM3,
                        child: const Center(
                          child: Text('Receipt Preview (Local File)'),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            if (entry.note != null && entry.note!.trim().isNotEmpty) ...[
              Text(
                'Note: ${entry.note}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              'Date: ${DateFormatter.formatFull(entry.date)}',
              style: AppTypography.labelSmall,
            ),
          ],
        ),
      );
    },
  );
}
