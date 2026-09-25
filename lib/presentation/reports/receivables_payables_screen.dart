import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_model.dart';
import '../../data/models/gst_models.dart';
import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/voucher_providers.dart';
import 'invoice_pdf_generator.dart';
import 'pdf_export_modal.dart';

enum AgingBucket {
  all,
  current30,
  days31To60,
  days61To90,
  overdue90;

  String get label {
    switch (this) {
      case AgingBucket.all:
        return 'All Invoices';
      case AgingBucket.current30:
        return '0–30 Days';
      case AgingBucket.days31To60:
        return '31–60 Days';
      case AgingBucket.days61To90:
        return '61–90 Days';
      case AgingBucket.overdue90:
        return '90+ Days (Overdue)';
    }
  }
}

class ReceivablesPayablesScreen extends ConsumerStatefulWidget {
  final bool initialIsPayables;

  const ReceivablesPayablesScreen({
    super.key,
    this.initialIsPayables = false,
  });

  @override
  ConsumerState<ReceivablesPayablesScreen> createState() =>
      _ReceivablesPayablesScreenState();
}

class _ReceivablesPayablesScreenState
    extends ConsumerState<ReceivablesPayablesScreen> {
  late bool _isPayables;
  AgingBucket _selectedBucket = AgingBucket.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _isPayables = widget.initialIsPayables;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _calculateDaysPastDue(VoucherModel v) {
    final now = DateTime.now();
    final referenceDate = v.dueDate ?? v.date;
    return now.difference(referenceDate).inDays;
  }

  bool _matchesBucket(VoucherModel v, AgingBucket bucket) {
    final days = _calculateDaysPastDue(v);
    switch (bucket) {
      case AgingBucket.all:
        return true;
      case AgingBucket.current30:
        return days <= 30;
      case AgingBucket.days31To60:
        return days > 30 && days <= 60;
      case AgingBucket.days61To90:
        return days > 60 && days <= 90;
      case AgingBucket.overdue90:
        return days > 90;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final company = ref.watch(activeCompanyProvider);
    final vouchersAsync = _isPayables
        ? ref.watch(payablesVouchersProvider)
        : ref.watch(receivablesVouchersProvider);
    final partiesList = ref.watch(partyListProvider).value ?? [];

    return AdaptiveScaffold(
      title: _isPayables ? 'Accounts Payable' : 'Accounts Receivable',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: Icon(isIos ? CupertinoIcons.refresh : Icons.refresh_rounded),
          onPressed: () {
            ref.invalidate(receivablesVouchersProvider);
            ref.invalidate(payablesVouchersProvider);
          },
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          return vouchersAsync.when(
            data: (vouchers) {
              // Filter by bucket and search
              final filtered = vouchers.where((v) {
                if (!_matchesBucket(v, _selectedBucket)) return false;
                if (_searchQuery.isNotEmpty) {
                  final party = (v.partyName ?? '').toLowerCase();
                  final num = v.voucherNumber.toLowerCase();
                  if (!party.contains(_searchQuery) && !num.contains(_searchQuery)) {
                    return false;
                  }
                }
                return true;
              }).toList();

              // Compute metrics
              int totalOutstandingCents = 0;
              int overdueCents = 0;
              for (final v in vouchers) {
                totalOutstandingCents += v.totalAmountInCents;
                if (_calculateDaysPastDue(v) > 0) {
                  overdueCents += v.totalAmountInCents;
                }
              }

              return RefreshIndicator.adaptive(
                onRefresh: () async {
                  HapticFeedback.lightImpact();
                  ref.invalidate(receivablesVouchersProvider);
                  ref.invalidate(payablesVouchersProvider);
                  ref.invalidate(partyListProvider);
                  ref.invalidate(businessSummaryProvider);
                  await ref.read(syncControllerProvider.notifier).triggerSync();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isWide ? 1100 : double.infinity),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Dual Segmented View: Receivables vs Payables
                          AdaptiveSegmentedControl<bool>(
                            groupValue: _isPayables,
                            children: const {
                              false: Text('Receivables (Customers)'),
                              true: Text('Payables (Vendors)'),
                            },
                            onValueChanged: (val) => setState(() => _isPayables = val),
                          ),
                          const SizedBox(height: 16),

                          // 2. Summary KPI Metrics Card
                          _buildKpiSummary(
                            context,
                            isIos: isIos,
                            totalOutstanding: totalOutstandingCents,
                            overdueAmount: overdueCents,
                            totalInvoices: vouchers.length,
                            isPayables: _isPayables,
                          ),
                          const SizedBox(height: 20),

                          // 3. Search Bar & Aging Bucket Filter Chips
                          _buildSearchAndFilters(context, isIos: isIos),
                          const SizedBox(height: 16),

                          // 4. Invoices / Bills List
                          if (filtered.isEmpty)
                            _buildEmptyState(context, isIos: isIos)
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final voucher = filtered[index];
                                Party? party;
                                if (voucher.partyId != null) {
                                  for (final p in partiesList) {
                                    if (p.id == voucher.partyId) {
                                      party = p;
                                      break;
                                    }
                                  }
                                }
                                return _buildInvoiceItemCard(
                                  context,
                                  voucher: voucher,
                                  party: party,
                                  company: company,
                                  isIos: isIos,
                                );
                              },
                            ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load records: $err'),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildKpiSummary(
    BuildContext context, {
    required bool isIos,
    required int totalOutstanding,
    required int overdueAmount,
    required int totalInvoices,
    required bool isPayables,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPayables
                    ? (isIos ? CupertinoIcons.arrow_up_circle_fill : Icons.upload_rounded)
                    : (isIos ? CupertinoIcons.arrow_down_circle_fill : Icons.download_rounded),
                color: isPayables ? AppColors.payableRed : AppColors.receivableGreen,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isPayables ? 'TOTAL VENDOR PAYABLES' : 'TOTAL CUSTOMER RECEIVABLES',
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CurrencyFormatter.format(totalOutstanding),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: isPayables ? AppColors.payableRed : AppColors.receivableGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalInvoices total ${isPayables ? "unpaid bills" : "outstanding invoices"}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: overdueAmount > 0
                      ? AppColors.payableRed.withValues(alpha: 0.12)
                      : AppColors.receivableGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'OVERDUE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: overdueAmount > 0 ? AppColors.payableRed : AppColors.receivableGreen,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(overdueAmount),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: overdueAmount > 0 ? AppColors.payableRed : AppColors.receivableGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 22,
        padding: EdgeInsets.zero,
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.75),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }

  Widget _buildSearchAndFilters(BuildContext context, {required bool isIos}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Input
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by party or invoice number...',
            prefixIcon: Icon(isIos ? CupertinoIcons.search : Icons.search_rounded),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 12),

        // Aging Bucket Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: AgingBucket.values.map((bucket) {
              final isSelected = _selectedBucket == bucket;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(bucket.label),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() => _selectedBucket = bucket);
                  },
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceItemCard(
    BuildContext context, {
    required VoucherModel voucher,
    required Party? party,
    required Company company,
    required bool isIos,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final daysPastDue = _calculateDaysPastDue(voucher);
    final isOverdue = daysPastDue > 0;

    final cardContent = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: _isPayables
                          ? AppColors.payableRed.withValues(alpha: 0.15)
                          : AppColors.receivableGreen.withValues(alpha: 0.15),
                      child: Text(
                        (voucher.partyName?.isNotEmpty ?? false)
                            ? voucher.partyName![0].toUpperCase()
                            : 'P',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isPayables ? AppColors.payableRed : AppColors.receivableGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            voucher.partyName ?? 'Party',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '#${voucher.voucherNumber} • ${DateFormatter.formatShortDate(voucher.date)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(voucher.totalAmountInCents),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _isPayables ? AppColors.payableRed : AppColors.receivableGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? AppColors.payableRed.withValues(alpha: 0.12)
                          : Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOverdue ? '$daysPastDue days overdue' : 'Due in ${daysPastDue.abs()} days',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isOverdue ? AppColors.payableRed : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // One-Click Action Buttons: Remind / Remittance Advice / View PDF
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 1. One-click Payment Reminder (WhatsApp/SMS/Share)
              TextButton.icon(
                onPressed: () => _sendPaymentReminder(context, voucher, party, company),
                icon: Icon(
                  isIos ? CupertinoIcons.bell_fill : Icons.notifications_active_rounded,
                  size: 16,
                  color: AppColors.primaryBlue,
                ),
                label: Text(
                  _isPayables ? 'Remittance Notice' : 'Send Reminder',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),

              // 2. One-click Remittance Advice / Receipt Export
              TextButton.icon(
                onPressed: () => _generateRemittanceAdvice(context, voucher, party, company),
                icon: Icon(
                  isIos ? CupertinoIcons.doc_plaintext : Icons.receipt_long_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                label: const Text(
                  'Advice / Receipt',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),

              // 3. View Full Invoice PDF
              IconButton(
                tooltip: 'Preview Invoice PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                onPressed: () => _previewInvoicePdf(context, voucher, party, company),
              ),
            ],
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 18,
        padding: EdgeInsets.zero,
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.75),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
        child: cardContent,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: cardContent,
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool isIos}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              isIos ? CupertinoIcons.checkmark_seal_fill : Icons.check_circle_outline_rounded,
              size: 52,
              color: AppColors.receivableGreen,
            ),
            const SizedBox(height: 12),
            Text(
              _isPayables ? 'No Outstanding Payables' : 'No Overdue Receivables',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'All invoices in the selected bucket have been settled.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPaymentReminder(
    BuildContext context,
    VoucherModel voucher,
    Party? party,
    Company company,
  ) async {
    HapticFeedback.mediumImpact();
    final partyName = voucher.partyName ?? party?.name ?? 'Valued Customer';
    final amountFormatted = CurrencyFormatter.format(voucher.totalAmountInCents);
    final dueDateFormatted = voucher.dueDate != null
        ? DateFormatter.formatShortDate(voucher.dueDate!)
        : DateFormatter.formatShortDate(voucher.date);

    final buffer = StringBuffer();
    if (_isPayables) {
      buffer.writeln('Remittance Notice from ${company.name}:');
      buffer.writeln('Bill #${voucher.voucherNumber} for $amountFormatted is scheduled for payment.');
      buffer.writeln('Vendor: $partyName');
    } else {
      buffer.writeln('Gentle Payment Reminder from ${company.name}:');
      buffer.writeln('Dear $partyName,');
      buffer.writeln('This is a friendly reminder that payment for Invoice #${voucher.voucherNumber} of $amountFormatted was due on $dueDateFormatted.');
      if (company.upiId != null && company.upiId!.isNotEmpty) {
        buffer.writeln('\nPay instantly via UPI: ${company.upiId}');
      }
      if (company.bankAccountNumber != null && company.bankAccountNumber!.isNotEmpty) {
        buffer.writeln('Bank: ${company.bankName ?? "Bank"} | A/C: ${company.bankAccountNumber} | IFSC: ${company.bankIfsc ?? ""}');
      }
      buffer.writeln('\nPlease notify us once payment has been remitted. Thank you for your business!');
    }

    final message = buffer.toString();
    final phone = party?.phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '') ?? '';

    if (phone.isNotEmpty) {
      final encoded = Uri.encodeComponent(message);
      final waUri = Uri.parse('whatsapp://send?phone=$phone&text=$encoded');
      final waWeb = Uri.parse('https://wa.me/$phone?text=$encoded');

      try {
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
          return;
        } else if (await canLaunchUrl(waWeb)) {
          await launchUrl(waWeb, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    // Fallback to system share sheet
    // ignore: deprecated_member_use
    await Share.share(message, subject: 'Payment Reminder #${voucher.voucherNumber}');
  }

  Future<void> _generateRemittanceAdvice(
    BuildContext context,
    VoucherModel voucher,
    Party? party,
    Company company,
  ) async {
    HapticFeedback.lightImpact();
    final effectiveParty = party ??
        Party(
          id: voucher.partyId ?? 'pty_temp',
          name: voucher.partyName ?? 'Party',
          phoneNumber: '',
          type: _isPayables ? PartyType.supplier : PartyType.customer,
          netBalanceInCents: voucher.totalAmountInCents,
          lastUpdated: DateTime.now(),
        );

    final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
      voucher: voucher,
      company: company,
      party: effectiveParty,
      templateType: InvoiceTemplateType.classicCorporate,
    );

    final fileName = '${_isPayables ? "RemittanceAdvice" : "PaymentReceipt"}_${voucher.voucherNumber}.pdf';

    if (kIsWeb) {
      if (context.mounted) {
        final dummyFile = File(fileName);
        PdfExportModal.show(
          context: context,
          pdfBytes: pdfBytes,
          file: dummyFile,
          fileName: fileName,
          partyName: effectiveParty.name,
          periodLabel: DateFormatter.formatShortDate(voucher.date),
          voucher: voucher,
          company: company,
          party: effectiveParty,
        );
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    if (context.mounted) {
      PdfExportModal.show(
        context: context,
        pdfBytes: pdfBytes,
        file: file,
        fileName: fileName,
        partyName: effectiveParty.name,
        periodLabel: DateFormatter.formatShortDate(voucher.date),
        partyPhone: effectiveParty.phoneNumber,
        voucher: voucher,
        company: company,
        party: effectiveParty,
      );
    }
  }

  Future<void> _previewInvoicePdf(
    BuildContext context,
    VoucherModel voucher,
    Party? party,
    Company company,
  ) async {
    HapticFeedback.lightImpact();
    final effectiveParty = party ??
        Party(
          id: voucher.partyId ?? 'pty_temp',
          name: voucher.partyName ?? 'Party',
          phoneNumber: '',
          type: _isPayables ? PartyType.supplier : PartyType.customer,
          netBalanceInCents: voucher.totalAmountInCents,
          lastUpdated: DateTime.now(),
        );

    final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
      voucher: voucher,
      company: company,
      party: effectiveParty,
      templateType: InvoiceTemplateType.gstStatutory,
    );

    final fileName = 'Invoice_${voucher.voucherNumber}.pdf';

    if (kIsWeb) {
      if (context.mounted) {
        final dummyFile = File(fileName);
        PdfExportModal.show(
          context: context,
          pdfBytes: pdfBytes,
          file: dummyFile,
          fileName: fileName,
          partyName: effectiveParty.name,
          periodLabel: DateFormatter.formatShortDate(voucher.date),
          voucher: voucher,
          company: company,
          party: effectiveParty,
        );
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    if (context.mounted) {
      PdfExportModal.show(
        context: context,
        pdfBytes: pdfBytes,
        file: file,
        fileName: fileName,
        partyName: effectiveParty.name,
        periodLabel: DateFormatter.formatShortDate(voucher.date),
        partyPhone: effectiveParty.phoneNumber,
        voucher: voucher,
        company: company,
        party: effectiveParty,
      );
    }
  }
}
