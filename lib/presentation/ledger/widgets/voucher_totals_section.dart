import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/adaptive_button.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../providers/gst_providers.dart';
import '../order_conversion_dialog.dart';
import 'voucher_adaptive_card.dart';
import 'voucher_form_controller.dart';

/// Totals, tax breakdown, compliance (e-Invoice/e-Way bill), and action buttons section.
class VoucherTotalsSection extends ConsumerWidget {
  final VoucherFormController controller;
  final Company company;
  final Party party;

  const VoucherTotalsSection({
    super.key,
    required this.controller,
    required this.company,
    required this.party,
  });

  Widget _buildSummaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final quota = ref.watch(subscriptionQuotaProvider);

    final isPurchase = controller.isPurchase;
    final isSalesOrder = controller.isSalesOrder;
    final isEstimate = controller.isEstimate;
    final isSalesInvoice = controller.isSalesInvoice;
    final accentColor = controller.getTypeAccentColor();
    final breakdown = controller.calculateBreakdown(company);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 6. Real-time Tax Breakdown Card
        VoucherAdaptiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isSalesInvoice
                        ? 'Output GST Computation Summary'
                        : isPurchase
                            ? 'Input Tax Credit (ITC) Summary'
                            : isSalesOrder
                                ? 'Order Value & Estimated Tax'
                                : 'Quotation Value & Estimated Tax',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (breakdown.isComposition)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Bill of Supply (Composition)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.brown),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSummaryLine('Taxable Subtotal', CurrencyFormatter.format(breakdown.subtotalInCents)),
              if (breakdown.cgstInCents > 0)
                _buildSummaryLine('Central GST (CGST)', CurrencyFormatter.format(breakdown.cgstInCents)),
              if (breakdown.sgstInCents > 0)
                _buildSummaryLine('State GST (SGST)', CurrencyFormatter.format(breakdown.sgstInCents)),
              if (breakdown.igstInCents > 0)
                _buildSummaryLine('Integrated GST (IGST)', CurrencyFormatter.format(breakdown.igstInCents)),
              if (breakdown.roundOffInCents != 0)
                _buildSummaryLine('Round-Off', CurrencyFormatter.format(breakdown.roundOffInCents)),
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isSalesInvoice
                        ? 'Total Invoice Value'
                        : isPurchase
                            ? 'Total Purchase Value'
                            : isSalesOrder
                                ? 'Total Order Value'
                                : 'Total Quotation Value',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    CurrencyFormatter.format(breakdown.totalAmountInCents),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accentColor),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 7. e-Invoice & e-Way Bill Government Portal Integration Card (Only for Sales Invoices)
        if (isSalesInvoice) ...[
          VoucherAdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'e-Invoice & e-Way Bill Portal',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Quota: ${quota.eInvoicesUsedThisMonth}/${quota.eInvoicesMonthlyQuota}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '2026 GSTN Rule Compliance: e-Invoice reporting is permitted for invoices dated within 30 days.',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (controller.complianceErrorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      controller.complianceErrorMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    // e-Invoice button
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: controller.isGeneratingEInvoice
                            ? () {}
                            : () => controller.generateEInvoice(company, party, context),
                        type: controller.generatedEInvoice != null
                            ? AdaptiveButtonType.secondary
                            : AdaptiveButtonType.primary,
                        height: 44,
                        child: controller.isGeneratingEInvoice
                            ? const CupertinoActivityIndicator(radius: 10)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    controller.generatedEInvoice != null
                                        ? (isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                                        : (isIos ? CupertinoIcons.qrcode : Icons.qr_code_2_rounded),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    controller.generatedEInvoice != null ? 'IRN Generated' : 'Generate IRN',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // e-Way Bill button
                    Expanded(
                      child: AdaptiveButton(
                        onPressed: controller.isGeneratingEWayBill
                            ? () {}
                            : () => controller.generateEWayBill(company, party, context),
                        type: controller.generatedEWayBill != null
                            ? AdaptiveButtonType.secondary
                            : AdaptiveButtonType.primary,
                        height: 44,
                        child: controller.isGeneratingEWayBill
                            ? const CupertinoActivityIndicator(radius: 10)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    controller.generatedEWayBill != null
                                        ? (isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                                        : (isIos ? CupertinoIcons.bus : Icons.local_shipping_rounded),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    controller.generatedEWayBill != null ? 'e-Way Active' : 'e-Way Bill',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 7b. Conversion Card if editing an existing Estimate or Sales Order
        if (controller.loadedVoucher != null &&
            (isEstimate || isSalesOrder) &&
            controller.currentStatus != VoucherStatus.converted) ...[
          VoucherAdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.transform_rounded, size: 20, color: AppColors.primaryBlue),
                    const SizedBox(width: 8),
                    Text(
                      'Document Conversion Workflow',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isEstimate
                      ? 'Convert this Quotation into a confirmed Sales Order or a posted Sales Invoice.'
                      : 'Convert this confirmed Sales Order into a posted Sales Invoice.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (isEstimate) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => OrderConversionDialog.show(context, controller.loadedVoucher!),
                          icon: const Icon(Icons.assignment_outlined, size: 16),
                          label: const Text('Convert Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => OrderConversionDialog.show(context, controller.loadedVoucher!),
                          icon: const Icon(Icons.receipt_long_rounded, size: 16),
                          label: const Text('Convert to Sales Invoice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 8. Secondary Draft / Hold Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.isSaving
                    ? null
                    : () => controller.saveVoucher(company, party, context, status: VoucherStatus.draft),
                icon: Icon(
                  isIos ? CupertinoIcons.pencil_ellipsis_rectangle : Icons.drafts_outlined,
                  size: 16,
                ),
                label: const Text(
                  'Save Draft',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (isSalesInvoice) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.isSaving
                      ? null
                      : () => controller.saveVoucher(company, party, context, status: VoucherStatus.onHold),
                  icon: Icon(
                    isIos ? CupertinoIcons.pause_circle : Icons.pause_circle_outline_rounded,
                    size: 16,
                    color: Colors.amber.shade800,
                  ),
                  label: Text(
                    'Hold Bill',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.amber.shade900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // 9. Main Action Buttons: Save / Post & Preview
        Row(
          children: [
            Expanded(
              child: AdaptiveButton(
                onPressed: () => controller.previewAndExportPdf(company, party, context),
                type: AdaptiveButtonType.secondary,
                height: 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.eye : Icons.visibility_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'Preview PDF',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AdaptiveButton(
                onPressed: controller.isSaving
                    ? () {}
                    : () => controller.saveVoucher(
                          company,
                          party,
                          context,
                          status: isSalesOrder
                              ? VoucherStatus.confirmed
                              : isEstimate
                                  ? VoucherStatus.posted
                                  : VoucherStatus.posted,
                        ),
                type: AdaptiveButtonType.primary,
                height: 52,
                child: controller.isSaving
                    ? const CupertinoActivityIndicator(radius: 12, color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isIos ? CupertinoIcons.checkmark : Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isSalesInvoice
                                  ? 'Post Invoice'
                                  : isPurchase
                                      ? 'Post Purchase'
                                      : isSalesOrder
                                          ? 'Confirm Order'
                                          : 'Save Quote',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
