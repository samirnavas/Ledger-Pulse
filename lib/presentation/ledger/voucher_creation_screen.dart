import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/voucher_providers.dart';
import 'widgets/voucher_form_controller.dart';
import 'widgets/voucher_header_section.dart';
import 'widgets/voucher_line_items_section.dart';
import 'widgets/voucher_totals_section.dart';

/// Screen for creating, drafting, and posting financial vouchers, sales orders, quotes, and bills.
class VoucherCreationScreen extends ConsumerStatefulWidget {
  final Party? initialParty;
  final VoucherType initialType;
  final VoucherModel? initialVoucher;

  const VoucherCreationScreen({
    super.key,
    this.initialParty,
    this.initialType = VoucherType.sales,
    this.initialVoucher,
  });

  @override
  ConsumerState<VoucherCreationScreen> createState() =>
      _VoucherCreationScreenState();
}

class _VoucherCreationScreenState extends ConsumerState<VoucherCreationScreen> {
  late final VoucherFormController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VoucherFormController(
      ref: ref,
      initialParty: widget.initialParty,
      initialType: widget.initialType,
      initialVoucher: widget.initialVoucher,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showDraftsSheet(BuildContext context) {
    final draftsAsync = ref.read(draftAndHeldVouchersProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      elevation: 0,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModalDragHandle(margin: EdgeInsets.only(bottom: 12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Draft & On-Hold Documents',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _controller.startFresh();
                    },
                    icon: Icon(
                      isIos ? CupertinoIcons.plus_circle : Icons.add_circle_outline,
                      size: 16,
                    ),
                    label: const Text('Start Fresh'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: draftsAsync.when(
                  data: (drafts) {
                    if (drafts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isIos ? CupertinoIcons.tray : Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No drafts or held documents found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      itemCount: drafts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final d = drafts[index];
                        final isOnHold = d.status == VoucherStatus.onHold;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          leading: CircleAvatar(
                            backgroundColor: isOnHold
                                ? Colors.amber.withValues(alpha: 0.2)
                                : Colors.blueGrey.withValues(alpha: 0.2),
                            child: Icon(
                              isOnHold
                                  ? (isIos
                                      ? CupertinoIcons.pause_fill
                                      : Icons.pause_circle_rounded)
                                  : (isIos
                                      ? CupertinoIcons.doc_text
                                      : Icons.drafts_rounded),
                              color: isOnHold
                                  ? Colors.amber.shade900
                                  : Colors.blueGrey.shade800,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                '#${d.voucherNumber}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOnHold
                                      ? Colors.amber.shade100
                                      : Colors.blueGrey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isOnHold ? 'ON HOLD' : 'DRAFT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isOnHold
                                        ? Colors.amber.shade900
                                        : Colors.blueGrey.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                d.type.displayName,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${d.partyName ?? "Party"} • ${d.items.length} items • ${DateFormatter.formatShortDate(d.date)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.format(d.totalAmountInCents),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Text('Resume >',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.primaryBlue)),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _controller.loadVoucher(d);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Loaded ${isOnHold ? "held bill" : "draft"} #${d.voucherNumber}'),
                                backgroundColor: AppColors.primaryBlue,
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error loading drafts: $e')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final company = ref.watch(activeCompanyProvider);

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final fallbackParty = _controller.selectedParty ??
            Party(
              id: _controller.isPurchase ? 'pty_temp_supp' : 'pty_temp_cust',
              name: _controller.isPurchase
                  ? 'Paramount Wholesale Suppliers'
                  : 'Apex Infotech Solutions',
              phoneNumber: '+91 98765 43210',
              type: _controller.isPurchase ? PartyType.supplier : PartyType.customer,
              netBalanceInCents: 0,
              gstin: _controller.partyGstinController.text.trim(),
              stateCode: _controller.placeOfSupplyController.text.trim(),
              lastUpdated: DateTime.now(),
            );

        final activeParty = _controller.selectedParty ?? fallbackParty;

        return AdaptiveScaffold(
          title: _controller.editingVoucherId != null
              ? 'Edit ${_controller.currentStatus == VoucherStatus.onHold ? "Held Bill" : _controller.currentStatus == VoucherStatus.draft ? "Draft" : _controller.selectedType.displayName}'
              : 'New ${_controller.selectedType.displayName}',
          actions: [
            Consumer(
              builder: (context, ref, _) {
                final draftsAsync = ref.watch(draftAndHeldVouchersProvider);
                final draftCount = draftsAsync.value?.length ?? 0;
                return IconButton(
                  tooltip: 'Drafts & Held Documents ($draftCount)',
                  icon: Badge(
                    isLabelVisible: draftCount > 0,
                    label: Text('$draftCount'),
                    child: Icon(
                      isIos
                          ? CupertinoIcons.tray_full
                          : Icons.folder_open_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onPressed: () => _showDraftsSheet(context),
                );
              },
            ),
            IconButton(
              tooltip: 'Preview PDF Document',
              icon: Icon(
                isIos
                    ? CupertinoIcons.doc_text_viewfinder
                    : Icons.picture_as_pdf_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () =>
                  _controller.previewAndExportPdf(company, activeParty, context),
            ),
          ],
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VoucherHeaderSection(
                  controller: _controller,
                  company: company,
                ),
                VoucherLineItemsSection(
                  controller: _controller,
                ),
                const SizedBox(height: 16),
                VoucherTotalsSection(
                  controller: _controller,
                  company: company,
                  party: activeParty,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
