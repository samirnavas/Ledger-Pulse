import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/amount_text.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../providers/ledger_providers.dart';
import '../reports/statement_preview_screen.dart';
import 'add_entry_bottom_sheet.dart';

class PartyLedgerScreen extends ConsumerWidget {
  final String partyId;

  const PartyLedgerScreen({
    super.key,
    required this.partyId,
  });

  void _openAddEntrySheet(
      BuildContext context, Party party, EntryType entryType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEntryBottomSheet(
        partyId: party.id,
        partyName: party.name,
        initialType: entryType,
      ),
    );
  }

  void _showReceiptDialog(BuildContext context, LedgerEntry entry) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bill / Receipt',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  entry.receiptPhotoUrl!,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Container(
                    height: 180,
                    color: AppColors.surfaceCardM3,
                    child: const Center(
                      child: Text('Receipt Preview (Offline Mock)'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (entry.note != null) ...[
                Text(
                  'Note: ${entry.note}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                'Date: ${DateFormatter.formatFull(entry.date)}',
                style: AppTypography.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    final partyAsync = ref.watch(partyDetailProvider(partyId));
    final entriesAsync = ref.watch(partyLedgerEntriesProvider(partyId));

    return partyAsync.when(
      loading: () => AdaptiveScaffold(
        title: 'Party Ledger',
        body: Center(
          child: isIos
              ? const CupertinoActivityIndicator()
              : const CircularProgressIndicator(),
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
            // Statement navigation icon
            IconButton(
              tooltip: 'Account Statement',
              icon: Icon(
                isIos ? CupertinoIcons.doc_text : Icons.description_outlined,
                size: 20,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  isIos
                      ? CupertinoPageRoute(
                          builder: (context) =>
                              StatementPreviewScreen(partyId: party.id),
                        )
                      : MaterialPageRoute(
                          builder: (context) =>
                              StatementPreviewScreen(partyId: party.id),
                        ),
                );
              },
            ),
          ],
          // Persistent Bottom Action Bar: Side-by-side [ - You Gave ] & [ + You Got ]
          bottomNavigationBar: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: isIos
                  ? CupertinoColors.systemBackground
                  : AppColors.surfaceWhite,
              border: const Border(
                top: BorderSide(color: AppColors.borderLight, width: 1),
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
                        Icon(Icons.arrow_upward_rounded, size: 20, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.youGave,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
                        Icon(Icons.arrow_downward_rounded, size: 20, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.youGot,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isIos
                      ? CupertinoColors.white
                      : AppColors.surfaceWhite,
                  border: const Border(
                    bottom: BorderSide(color: AppColors.borderLight, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Phone & Quick Call Action
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          party.phoneNumber,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Calling ${party.phoneNumber}...'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlueLight.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isIos
                                      ? CupertinoIcons.phone_fill
                                      : Icons.call_rounded,
                                  size: 13,
                                  color: AppColors.primaryBlue,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  AppStrings.callParty,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: party.netBalanceInCents > 0
                                ? AppColors.receivableGreenDark
                                : party.netBalanceInCents < 0
                                    ? AppColors.payableRedDark
                                    : AppColors.textSecondaryLight,
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
                  loading: () => Center(
                    child: isIos
                        ? const CupertinoActivityIndicator()
                        : const CircularProgressIndicator(),
                  ),
                  error: (err, _) => Center(child: Text('Error: $err')),
                  data: (entries) {
                    if (entries.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 56,
                              color: AppColors.textMutedLight.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No transactions yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap You Gave or You Got below to create an entry.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMutedLight,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isGave = entry.type == EntryType.gave;
                        final color = isGave
                            ? AppColors.payableRed
                            : AppColors.receivableGreen;

                        // Check if group header should be shown (grouping by date)
                        final showHeader = index == 0 ||
                            DateFormatter.formatRelative(entries[index - 1].date) !=
                                DateFormatter.formatRelative(entry.date);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 12, bottom: 8),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceCardM3,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      DateFormatter.formatRelative(entry.date),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            // Ledger Entry Row
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isIos
                                    ? CupertinoColors.white
                                    : AppColors.surfaceWhite,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.borderLight,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.015),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Entry Type Badge Tag ("GAVE" / "GOT")
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isGave ? 'GAVE' : 'GOT',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Note & Timestamp & Optional Bill Icon
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.note ?? (isGave ? 'You Gave' : 'You Got'),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimaryLight,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Text(
                                              DateFormatter.formatTime(entry.date),
                                              style: AppTypography.labelSmall,
                                            ),
                                            if (entry.receiptPhotoUrl != null) ...[
                                              const SizedBox(width: 6),
                                              GestureDetector(
                                                onTap: () => _showReceiptDialog(
                                                    context, entry),
                                                child: Row(
                                                  children: const [
                                                    Icon(
                                                      Icons.receipt_rounded,
                                                      size: 14,
                                                      color: AppColors.primaryBlue,
                                                    ),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'Bill',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.primaryBlue,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
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
                                        CurrencyFormatter.format(entry.amountInCents),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                        ),
                                      ),
                                      if (entry.runningBalanceInCents != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Bal: ${CurrencyFormatter.format(entry.runningBalanceInCents!)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textSecondaryLight,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
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
