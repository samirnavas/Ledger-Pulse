import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/voucher_model.dart';
import '../home/add_party_dialog.dart';
import '../providers/ledger_providers.dart';
import '../providers/sync_providers.dart';
import '../reports/statement_preview_screen.dart';
import 'add_entry_bottom_sheet.dart';
import 'voucher_creation_screen.dart';
import 'widgets/animated_party_ledger_list.dart';
import 'widgets/party_bottom_action_bar.dart';
import 'widgets/party_context_menu.dart';
import 'widgets/party_ledger_hero_header.dart';
import 'widgets/party_transaction_voucher_sheet.dart';

class PartyLedgerScreen extends ConsumerWidget {
  final String partyId;

  const PartyLedgerScreen({super.key, required this.partyId});

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
      showDragHandle: false,
      elevation: 0,
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

  void _openAddEntrySheet(
    BuildContext context,
    Party party,
    EntryType entryType,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      elevation: 0,
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
      showDragHandle: false,
      elevation: 0,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);

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
              onPressed: () => showPartyContextMenu(
                context: context,
                party: party,
                onEditParty: () => _openEditParty(context, party),
                onDeleteParty: () => _handleDeleteParty(context, ref, party),
              ),
            ),
          ],
          body: Column(
            children: [
              // 1. Top Sticky Header: Contact info, Quick Call, and Net Balance
              PartyLedgerHeroHeader(
                party: party,
                onCall: () => _makePhoneCall(context, party.phoneNumber),
              ),

              // 2. Chronological Ledger Stream with fading bottom bar
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RefreshIndicator.adaptive(
                        onRefresh: () async {
                          HapticFeedback.lightImpact();
                          ref.invalidate(partyLedgerEntriesProvider(partyId));
                          ref.invalidate(partyByIdProvider(partyId));
                          ref.invalidate(partyListProvider);
                          ref.invalidate(businessSummaryProvider);
                          await ref
                              .read(syncControllerProvider.notifier)
                              .triggerSync();
                        },
                        child: entriesAsync.when(
                          loading: () => ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              110 + MediaQuery.paddingOf(context).bottom,
                            ),
                            itemCount: 6,
                            itemBuilder: (context, index) =>
                                const SkeletonLedgerTile(),
                          ),
                          error: (err, _) => ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 60,
                                ),
                                child: Center(child: Text('Error: $err')),
                              ),
                            ],
                          ),
                          data: (entries) {
                            if (entries.isEmpty) {
                              return ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(
                                  0,
                                  40,
                                  0,
                                  110 + MediaQuery.paddingOf(context).bottom,
                                ),
                                children: [
                                  EmptyStateView(
                                    lottieAsset:
                                        'assets/animations/empty_ledger.json',
                                    fallbackIcon: isIos
                                        ? CupertinoIcons.doc_plaintext
                                        : Icons.receipt_long_outlined,
                                    title: 'No Transactions Yet',
                                    subtitle:
                                        'Tap You Gave or You Got below to create the first transaction entry.',
                                  ),
                                ],
                              );
                            }

                            return Column(
                              children: [
                                // Top List Column Indicator (One indicator for all list)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    6,
                                    16,
                                    6,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        'ENTRIES',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
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
                                          color: AppColors.payableRed
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
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
                                          color: AppColors.receivableGreen
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(
                                        alpha: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? 0.2
                                            : 0.35,
                                      ),
                                ),
                                Expanded(
                                  child: AnimatedPartyLedgerList(
                                    entries: entries,
                                    isIos: isIos,
                                    onShowReceipt: showReceiptImageDialog,
                                    onOpenVoucher: (ctx, entry) =>
                                        showTransactionDetailSheet(
                                      context: ctx,
                                      entry: entry,
                                      party: party,
                                      onEditEntry: () =>
                                          _openEditEntrySheet(ctx, party, entry),
                                      onVoidEntry: () =>
                                          _handleVoidEntry(ctx, ref, entry, party),
                                      onShowReceipt: showReceiptImageDialog,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    // Floating Gradient Fade Bottom Action Bar (You Gave / You Got)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: PartyBottomActionBar(
                        onYouGave: () =>
                            _openAddEntrySheet(context, party, EntryType.gave),
                        onYouGot: () =>
                            _openAddEntrySheet(context, party, EntryType.got),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
