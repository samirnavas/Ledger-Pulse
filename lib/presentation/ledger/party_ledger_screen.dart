import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/voucher_model.dart';
import 'package:url_launcher/url_launcher.dart';
import '../home/add_party_dialog.dart';
import '../providers/ledger_providers.dart';
import '../reports/statement_preview_screen.dart';
import 'add_entry_bottom_sheet.dart';
import 'voucher_creation_screen.dart';

class PartyLedgerScreen extends ConsumerWidget {
  final String partyId;

  const PartyLedgerScreen({super.key, required this.partyId});

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<void> _makePhoneCall(BuildContext context, String phoneNumber) async {
    HapticFeedback.lightImpact();
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanNumber');
    final uriWithSlashes = Uri.parse('tel://$cleanNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (await canLaunchUrl(uriWithSlashes)) {
        await launchUrl(uriWithSlashes);
      } else {
        await launchUrl(uriWithSlashes);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not place call to $phoneNumber: $e')),
        );
      }
    }
  }

  void _openEditParty(BuildContext context, Party party) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddPartyDialog(
        initialType: party.type,
        partyToEdit: party,
      ),
    );
  }

  Future<void> _handleDeleteParty(
    BuildContext context,
    WidgetRef ref,
    Party party,
  ) async {
    // 1. Safety Check: Verify if party.netBalanceInCents != 0
    if (party.netBalanceInCents != 0) {
      final formattedBalance = CurrencyFormatter.format(
        party.netBalanceInCents,
        absolute: true,
      );
      await showAdaptiveInfoDialog(
        context: context,
        title: 'Cannot Delete Party',
        message:
            'Cannot delete a party with an outstanding balance of $formattedBalance. Settle the dues first.',
        buttonLabel: 'OK',
      );
      return;
    }

    // 2. Open Adaptive Confirmation Dialog for 0-balance party
    final shouldDelete = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Delete Party?',
      message:
          'Are you sure you want to delete ${party.name}? All transaction records for this party will be archived.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );

    if (shouldDelete && context.mounted) {
      try {
        await ref.read(ledgerActionControllerProvider).deleteParty(party.id);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${party.name} deleted and archived.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).colorScheme.inverseSurface,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete party: $e'),
              backgroundColor: AppColors.payableRed,
            ),
          );
        }
      }
    }
  }

  void _showPartyContextMenu(
    BuildContext context,
    WidgetRef ref,
    Party party,
  ) {
    HapticFeedback.mediumImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(party.name),
          message: Text(party.phoneNumber),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openEditParty(context, party);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.pencil, size: 20),
                  SizedBox(width: 8),
                  Text('Edit Details'),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(ctx).pop();
                _handleDeleteParty(context, ref, party);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.trash, size: 20),
                  SizedBox(width: 8),
                  Text('Delete Party'),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      final colorScheme = Theme.of(context).colorScheme;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        party.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        party.phoneNumber,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text(
                          'Edit Details',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openEditParty(context, party);
                        },
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 56,
                        endIndent: 16,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          'Delete Party',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.error,
                          ),
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(16)),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _handleDeleteParty(context, ref, party);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _openAddEntrySheet(
    BuildContext context,
    Party party,
    EntryType entryType,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (context) => AddEntryBottomSheet(
        partyId: party.id,
        partyName: party.name,
        initialType: entryType,
      ),
    );
  }

  void _openEditEntrySheet(
    BuildContext context,
    Party party,
    LedgerEntry entry,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (context) => AddEntryBottomSheet(
        partyId: party.id,
        partyName: party.name,
        initialType: entry.type,
        entryToEdit: entry,
      ),
    );
  }

  Future<void> _handleVoidEntry(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
    Party party,
  ) async {
    HapticFeedback.lightImpact();
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Void Transaction?',
      message:
          'Void this entry? A reversing entry will be added to balance the ledger.',
      confirmLabel: 'Void Entry',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );

    if (confirmed && context.mounted) {
      HapticFeedback.mediumImpact();
      await ref
          .read(ledgerActionControllerProvider)
          .deleteEntry(entry.id, party.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction voided. Reversing entry recorded.'),
            backgroundColor: AppColors.payableRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showTransactionDetailSheet(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
    Party party,
  ) {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGave = entry.type == EntryType.gave;
    final color = isGave ? AppColors.payableRed : AppColors.receivableGreen;

    showModalBottomSheet(
      context: context,
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isIos
                              ? CupertinoIcons.doc_text
                              : Icons.receipt_long_rounded,
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
                    IconButton(
                      icon: Icon(
                        isIos
                            ? CupertinoIcons.xmark_circle_fill
                            : Icons.close_rounded,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Voucher Summary Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isIos
                        ? (isDark
                            ? CupertinoColors.systemGrey6
                            : CupertinoColors.white)
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
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
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
                                color: AppColors.payableRed
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.payableRed
                                      .withValues(alpha: 0.3),
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
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                          color: entry.isVoided
                              ? color.withValues(alpha: 0.45)
                              : color,
                          decoration:
                              entry.isVoided ? TextDecoration.lineThrough : null,
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
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 10),
                      _buildVoucherRow(
                        context: sheetContext,
                        label: 'Date & Time',
                        value: DateFormatter.formatFull(entry.date),
                        icon: Icons.access_time_rounded,
                      ),
                      const SizedBox(height: 10),
                      _buildVoucherRow(
                        context: sheetContext,
                        label: 'Note',
                        value:
                            entry.note != null && entry.note!.trim().isNotEmpty
                                ? entry.note!
                                : 'No note provided',
                        icon: Icons.notes_rounded,
                      ),
                      if (entry.runningBalanceInCents != null) ...[
                        const SizedBox(height: 10),
                        _buildVoucherRow(
                          context: sheetContext,
                          label: 'Running Balance',
                          value: CurrencyFormatter.format(
                            entry.runningBalanceInCents!,
                          ),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ],
                      if (entry.receiptPhotoUrl != null) ...[
                        const SizedBox(height: 14),
                        InkWell(
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _showReceiptDialog(context, entry);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 20,
                                  color: Theme.of(sheetContext)
                                      .colorScheme
                                      .primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Attached Bill Receipt',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(sheetContext)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                      Text(
                                        'Tap to view receipt image preview',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(sheetContext)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: Theme.of(sheetContext)
                                      .colorScheme
                                      .primary,
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
                            _openEditEntrySheet(context, party, entry);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text(
                            'Edit Note / Details',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
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
                            _handleVoidEntry(context, ref, entry, party);
                          },
                          icon: const Icon(
                            Icons.delete_outline_rounded,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.payableRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.payableRed.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.payableRed,
                        ),
                        SizedBox(width: 8),
                        Text(
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

  void _showReceiptDialog(BuildContext context, LedgerEntry entry) {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bill / Receipt',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isIos ? CupertinoIcons.xmark_circle_fill : Icons.close_rounded,
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final partyAsync = ref.watch(partyDetailProvider(partyId));
    final entriesAsync = ref.watch(partyLedgerEntriesProvider(partyId));

    return partyAsync.when(
      loading: () => AdaptiveScaffold(
        title: 'Party Ledger',
        body: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: 6,
          itemBuilder: (context, index) => const SkeletonLedgerTile(),
        ),
      ),
      error: (err, _) => AdaptiveScaffold(
        title: 'Party Ledger',
        body: Center(child: Text('Error: $err')),
      ),
      data: (party) {
        return AdaptiveScaffold(
          title: party.name,
          actions: [
            // Create Tax Invoice button
            IconButton(
              tooltip: 'New Tax Invoice',
              icon: Icon(
                isIos ? CupertinoIcons.doc_append : Icons.receipt_long_rounded,
                size: 20,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  createAdaptivePageRoute(
                    builder: (context) => VoucherCreationScreen(
                      initialParty: party,
                      initialType: VoucherType.sales,
                    ),
                    transitionType: SharedAxisTransitionType.horizontal,
                  ),
                );
              },
            ),
            // Statement navigation icon
            IconButton(
              tooltip: 'Account Statement',
              icon: Icon(
                isIos ? CupertinoIcons.doc_text : Icons.description_outlined,
                size: 20,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  createAdaptivePageRoute(
                    builder: (context) =>
                        StatementPreviewScreen(partyId: party.id),
                    transitionType: SharedAxisTransitionType.horizontal,
                  ),
                );
              },
            ),
            // Party Context Menu (Edit & Delete)
            IconButton(
              tooltip: 'Party Options',
              icon: Icon(
                isIos ? CupertinoIcons.ellipsis : Icons.more_vert_rounded,
                size: 20,
              ),
              onPressed: () => _showPartyContextMenu(context, ref, party),
            ),
          ],
          // Persistent Bottom Action Bar: Side-by-side [ - You Gave ] & [ + You Got ]
          bottomNavigationBar: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
            decoration: BoxDecoration(
              color: isIos
                  ? CupertinoColors.systemBackground
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.35
                            : 0.5,
                      ),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                // - You Gave (Red)
                Expanded(
                  child: AdaptiveButton(
                    onPressed: () =>
                        _openAddEntrySheet(context, party, EntryType.gave),
                    type: AdaptiveButtonType.destructive,
                    height: 52,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.arrow_upward_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.youGave,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // + You Got (Green)
                Expanded(
                  child: AdaptiveButton(
                    onPressed: () =>
                        _openAddEntrySheet(context, party, EntryType.got),
                    type: AdaptiveButtonType.success,
                    height: 52,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.youGot,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              // 1. Top Sticky Header: Contact info, Quick Call, and Net Balance
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isIos
                      ? (isDark
                            ? CupertinoColors.systemBackground.darkColor
                            : CupertinoColors.white)
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant
                          .withValues(alpha: isDark ? 0.35 : 0.5),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (!isIos) ...[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _getInitials(party.name),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        // Phone & Quick Call Action
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () =>
                                  _makePhoneCall(context, party.phoneNumber),
                              child: Text(
                                party.phoneNumber,
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: () =>
                                  _makePhoneCall(context, party.phoneNumber),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: isDark ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isIos
                                          ? CupertinoIcons.phone_fill
                                          : Icons.call_rounded,
                                      size: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      AppStrings.callParty,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Net Balance in Bold Typography
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          party.netBalanceInCents > 0
                              ? "YOU'LL GET"
                              : party.netBalanceInCents < 0
                              ? "YOU'LL GIVE"
                              : 'SETTLED',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: party.netBalanceInCents > 0
                                ? (isDark
                                      ? const Color(0xFF4ADE80)
                                      : AppColors.receivableGreenDark)
                                : party.netBalanceInCents < 0
                                ? (isDark
                                      ? const Color(0xFFF87171)
                                      : AppColors.payableRedDark)
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AmountText(
                          amountInCents: party.netBalanceInCents,
                          variant: AmountVariant.large,
                          absolute: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Chronological Ledger Stream
              Expanded(
                child: entriesAsync.when(
                  loading: () => ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: 6,
                    itemBuilder: (context, index) => const SkeletonLedgerTile(),
                  ),
                  error: (err, _) => Center(child: Text('Error: $err')),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return const EmptyStateView(
                        lottieAsset: 'assets/animations/empty_ledger.json',
                        fallbackIcon: Icons.receipt_long_outlined,
                        title: 'No Transactions Yet',
                        subtitle:
                            'Tap You Gave or You Got below to create the first transaction entry.',
                      );
                    }

                    return Column(
                      children: [
                        // Top List Column Indicator (One indicator for all list)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Row(
                            children: [
                              Text(
                                'ENTRIES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.payableRed.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'GAVE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.payableRed,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.receivableGreen.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'GOT',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.receivableGreen,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          endIndent: 16,
                          color: Theme.of(context).colorScheme.outlineVariant
                              .withValues(
                                alpha:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.2
                                    : 0.35,
                              ),
                        ),
                        Expanded(
                          child: _AnimatedPartyLedgerList(
                            entries: entries,
                            isIos: isIos,
                            onShowReceipt: _showReceiptDialog,
                            onOpenVoucher: (ctx, entry) =>
                                _showTransactionDetailSheet(
                              ctx,
                              ref,
                              entry,
                              party,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedPartyLedgerList extends StatefulWidget {
  final List<LedgerEntry> entries;
  final bool isIos;
  final void Function(BuildContext, LedgerEntry) onShowReceipt;
  final void Function(BuildContext, LedgerEntry) onOpenVoucher;

  const _AnimatedPartyLedgerList({
    required this.entries,
    required this.isIos,
    required this.onShowReceipt,
    required this.onOpenVoucher,
  });

  @override
  State<_AnimatedPartyLedgerList> createState() =>
      _AnimatedPartyLedgerListState();
}

class _AnimatedPartyLedgerListState extends State<_AnimatedPartyLedgerList> {
  final Set<String> _knownEntryIds = {};
  final Set<String> _newlyAddedEntryIds = {};

  @override
  void initState() {
    super.initState();
    for (final e in widget.entries) {
      _knownEntryIds.add(e.id);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedPartyLedgerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final e in widget.entries) {
      if (!_knownEntryIds.contains(e.id)) {
        _knownEntryIds.add(e.id);
        _newlyAddedEntryIds.add(e.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        final isGave = entry.type == EntryType.gave;
        final color = isGave ? AppColors.payableRed : AppColors.receivableGreen;
        final isNew = _newlyAddedEntryIds.contains(entry.id);

        // Check if group header should be shown (grouping by date)
        final showHeader =
            index == 0 ||
            DateFormatter.formatRelative(widget.entries[index - 1].date) !=
                DateFormatter.formatRelative(entry.date);

        final Widget plainRowContent = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onOpenVoucher(context, entry);
            },
            onLongPress: () {
              HapticFeedback.lightImpact();
              widget.onOpenVoucher(context, entry);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: _buildRowContent(context, entry, isGave, color),
            ),
          ),
        );

        Widget rowWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: index == 0 ? 6 : 14,
                  bottom: 4,
                ),
                child: Text(
                  DateFormatter.formatRelative(entry.date),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
            _HighlightedLedgerCard(
              key: ValueKey('highlight_${entry.id}'),
              isNew: isNew,
              highlightColor: color,
              onHighlightComplete: () {
                _newlyAddedEntryIds.remove(entry.id);
              },
              child: plainRowContent,
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.2 : 0.35,
              ),
            ),
          ],
        );

        if (isNew) {
          rowWidget = rowWidget
              .animate(key: ValueKey('anim_${entry.id}'))
              .fadeIn(duration: 300.ms, curve: Curves.easeOut)
              .slideY(
                begin: -0.35,
                end: 0,
                duration: 300.ms,
                curve: Curves.easeOutCubic,
              );
        }

        return rowWidget;
      },
    );
  }

  Widget _buildRowContent(
    BuildContext context,
    LedgerEntry entry,
    bool isGave,
    Color color,
  ) {
    final effectiveColor =
        entry.isVoided ? color.withValues(alpha: 0.45) : color;

    return Row(
      children: [
        // Note & Timestamp & Optional Bill Icon
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.note ?? (isGave ? 'You Gave' : 'You Got'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: entry.isVoided
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.45)
                            : Theme.of(context).colorScheme.onSurface,
                        decoration: entry.isVoided
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.isVoided) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.payableRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'VOID',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.payableRed,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    DateFormatter.formatTime(entry.date),
                    style: AppTypography.labelSmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.receiptPhotoUrl != null) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onShowReceipt(context, entry);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Bill',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 11,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // Amount & Running Balance Indicator
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isGave ? "-" : "+"} ${CurrencyFormatter.format(entry.amountInCents)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: effectiveColor,
                decoration:
                    entry.isVoided ? TextDecoration.lineThrough : null,
              ),
            ),
            if (entry.runningBalanceInCents != null) ...[
              const SizedBox(height: 2),
              Text(
                'Bal: ${CurrencyFormatter.format(entry.runningBalanceInCents!)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _HighlightedLedgerCard extends StatefulWidget {
  final Widget child;
  final bool isNew;
  final Color highlightColor;
  final VoidCallback? onHighlightComplete;

  const _HighlightedLedgerCard({
    super.key,
    required this.child,
    required this.isNew,
    required this.highlightColor,
    this.onHighlightComplete,
  });

  @override
  State<_HighlightedLedgerCard> createState() => _HighlightedLedgerCardState();
}

class _HighlightedLedgerCardState extends State<_HighlightedLedgerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    if (widget.isNew) {
      _controller.forward().then((_) {
        widget.onHighlightComplete?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNew) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final flashAlpha = (1.0 - _animation.value) * 0.28;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: widget.highlightColor.withValues(alpha: flashAlpha),
            border: flashAlpha > 0.05
                ? Border.all(
                    color: widget.highlightColor.withValues(
                      alpha: flashAlpha * 1.5,
                    ),
                    width: 1.5,
                  )
                : null,
            boxShadow: flashAlpha > 0.05
                ? [
                    BoxShadow(
                      color: widget.highlightColor.withValues(
                        alpha: flashAlpha * 0.4,
                      ),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
