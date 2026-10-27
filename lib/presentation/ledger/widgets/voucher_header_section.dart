import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/adaptive_button.dart';
import '../../../core/widgets/adaptive_segmented_control.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../providers/ledger_providers.dart';
import 'voucher_adaptive_card.dart';
import 'voucher_form_controller.dart';

/// Header section of VoucherCreationScreen: type picker, document details, party selection, and consignee.
class VoucherHeaderSection extends ConsumerWidget {
  final VoucherFormController controller;
  final Company company;

  const VoucherHeaderSection({
    super.key,
    required this.controller,
    required this.company,
  });

  Future<void> _showAdaptiveDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required ValueChanged<DateTime> onDateSelected,
  }) async {
    final isIos = AdaptiveThemeHelper.isIos(context);
    if (isIos) {
      DateTime tempPicked = initialDate;
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => Container(
          height: 280,
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onDateSelected(tempPicked);
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initialDate,
                  minimumDate: DateTime(2020),
                  maximumDate: DateTime(2035),
                  onDateTimeChanged: (d) => tempPicked = d,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              headerBackgroundColor: Theme.of(context).colorScheme.primary,
              headerForegroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          child: child!,
        ),
      );
      if (picked != null) {
        onDateSelected(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final partiesAsync = ref.watch(partyListProvider);

    final isPurchase = controller.isPurchase;
    final isSalesOrder = controller.isSalesOrder;
    final isSalesInvoice = controller.isSalesInvoice;
    final accentColor = controller.getTypeAccentColor();
    final breakdown = controller.calculateBreakdown(company);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editing Banner
        if (controller.editingVoucherId != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: controller.currentStatus == VoucherStatus.onHold
                  ? Colors.amber.withValues(alpha: 0.15)
                  : Colors.blueGrey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: controller.currentStatus == VoucherStatus.onHold
                    ? Colors.amber.shade700
                    : Colors.blueGrey.shade400,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  controller.currentStatus == VoucherStatus.onHold
                      ? (isIos ? CupertinoIcons.pause_circle_fill : Icons.pause_circle_rounded)
                      : (isIos ? CupertinoIcons.doc_text_fill : Icons.drafts_rounded),
                  color: controller.currentStatus == VoucherStatus.onHold
                      ? Colors.amber.shade900
                      : Colors.blueGrey.shade900,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Editing ${controller.selectedType.displayName} #${controller.voucherNumberController.text} (${controller.currentStatus.displayName})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: controller.currentStatus == VoucherStatus.onHold
                          ? Colors.amber.shade900
                          : Colors.blueGrey.shade900,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => controller.startFresh(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      'Save as New',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 1. Voucher Type Segmented Control
        AdaptiveSegmentedControl<VoucherType>(
          groupValue: controller.selectedType,
          children: const {
            VoucherType.sales: Text('Sales Invoice'),
            VoucherType.salesOrder: Text('Sales Order'),
            VoucherType.estimate: Text('Estimate / Quote'),
            VoucherType.purchase: Text('Purchase Bill'),
          },
          onValueChanged: controller.onTypeChanged,
        ),
        const SizedBox(height: 12),

        // Document Workflow Status Indicator & Helper Note
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                isSalesInvoice
                    ? Icons.receipt_long_rounded
                    : isPurchase
                        ? Icons.shopping_bag_rounded
                        : isSalesOrder
                            ? Icons.assignment_turned_in_rounded
                            : Icons.format_quote_rounded,
                size: 18,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSalesInvoice
                      ? 'Sales Invoice: Posts revenue, output GST, customer receivable & reduces inventory.'
                      : isPurchase
                          ? 'Purchase Bill: Posts COGS, input tax credit (ITC), supplier payable & increases inventory.'
                          : isSalesOrder
                              ? 'Sales Order: Confirmed customer order. Does NOT affect accounting or inventory until converted.'
                              : 'Estimate / Quotation: Price quote. Does NOT affect accounting or inventory until converted.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Adaptive Header Card (Document #, Dates, References)
        VoucherAdaptiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.voucherNumberController,
                      decoration: InputDecoration(
                        labelText: isSalesInvoice
                            ? 'Invoice Number'
                            : isPurchase
                                ? 'Purchase Bill #'
                                : isSalesOrder
                                    ? 'Sales Order #'
                                    : 'Quote / Estimate #',
                        isDense: true,
                        prefixIcon: Icon(
                          isIos ? CupertinoIcons.number : Icons.tag_rounded,
                          size: 20,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _showAdaptiveDatePicker(
                        context: context,
                        initialDate: controller.voucherDate,
                        onDateSelected: controller.setVoucherDate,
                      ),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: isSalesInvoice
                              ? 'Invoice Date'
                              : isPurchase
                                  ? 'Bill Date'
                                  : isSalesOrder
                                      ? 'Order Date'
                                      : 'Quote Date',
                          isDense: true,
                          prefixIcon: Icon(
                            isIos ? CupertinoIcons.calendar : Icons.calendar_today_rounded,
                            size: 18,
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(DateFormatter.formatShortDate(controller.voucherDate)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Due / Delivery / Expiry Date
                  Expanded(
                    child: InkWell(
                      onTap: () => _showAdaptiveDatePicker(
                        context: context,
                        initialDate: controller.dueDate ??
                            controller.voucherDate.add(const Duration(days: 15)),
                        onDateSelected: controller.setDueDate,
                      ),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: isSalesInvoice
                              ? 'Payment Due Date'
                              : isPurchase
                                  ? 'Payment Due Date'
                                  : isSalesOrder
                                      ? 'Expected Delivery'
                                      : 'Valid Until / Expiry',
                          isDense: true,
                          prefixIcon: Icon(
                            isIos ? CupertinoIcons.time : Icons.event_available_rounded,
                            size: 18,
                          ),
                          suffixIcon: controller.dueDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () => controller.setDueDate(null),
                                )
                              : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          controller.dueDate != null
                              ? DateFormatter.formatShortDate(controller.dueDate!)
                              : 'Not specified',
                          style: TextStyle(
                            color: controller.dueDate != null
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Supplier Invoice Ref / PO Reference
                  Expanded(
                    child: TextField(
                      controller: controller.referenceNumberController,
                      decoration: InputDecoration(
                        labelText: isPurchase
                            ? 'Supplier Invoice Ref #'
                            : 'Reference / PO #',
                        hintText: isPurchase ? 'e.g. SUPP-INV-99' : 'Optional PO #',
                        isDense: true,
                        prefixIcon: Icon(
                          isIos ? CupertinoIcons.doc_plaintext : Icons.receipt_outlined,
                          size: 18,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Place of Supply & Tax Nature
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.placeOfSupplyController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Place of Supply (State Code)',
                        hintText: 'e.g. 29 (Karnataka), 27 (Maharashtra)',
                        isDense: true,
                        prefixIcon: Icon(
                          isIos ? CupertinoIcons.location : Icons.location_on_rounded,
                          size: 20,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: breakdown.isIntraState
                          ? AppColors.receivableGreen.withValues(alpha: 0.15)
                          : Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      breakdown.isIntraState ? 'Intra-State (CGST+SGST)' : 'Inter-State (IGST)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: breakdown.isIntraState ? AppColors.receivableGreen : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Party & Live GSTIN Validation Card
        VoucherAdaptiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isPurchase ? 'Supplier / Vendor Details' : 'Customer & GSTIN Details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  partiesAsync.when(
                    data: (parties) {
                      final filteredParties = parties.where((p) {
                        if (isPurchase) return p.type == PartyType.supplier;
                        return p.type == PartyType.customer;
                      }).toList();

                      return DropdownButton<String>(
                        value: filteredParties.any((p) => p.id == controller.selectedParty?.id)
                            ? controller.selectedParty?.id
                            : null,
                        hint: Text(
                          isPurchase ? 'Select Supplier' : 'Select Customer',
                          style: const TextStyle(fontSize: 13),
                        ),
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        items: filteredParties
                            .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                            .toList(),
                        onChanged: (id) {
                          if (id != null) {
                            final party = filteredParties.firstWhere((p) => p.id == id);
                            controller.setParty(party);
                          }
                        },
                      );
                    },
                    loading: () => const CupertinoActivityIndicator(radius: 8),
                    error: (err, stack) => const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller.partyGstinController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: isPurchase ? 'Supplier GSTIN' : 'Party GSTIN',
                        hintText: '15-digit alphanumeric',
                        isDense: true,
                        prefixIcon: Icon(
                          isIos ? CupertinoIcons.shield_lefthalf_fill : Icons.verified_user_rounded,
                          size: 20,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  controller.isValidatingGstin
                      ? const CupertinoActivityIndicator(radius: 12)
                      : AdaptiveButton(
                          onPressed: controller.validateGstin,
                          type: AdaptiveButtonType.secondary,
                          height: 48,
                          child: const Text('Verify'),
                        ),
                ],
              ),
              if (controller.gstinValidationResult != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: controller.gstinValidationResult!.isValid
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        controller.gstinValidationResult!.isValid
                            ? (isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                            : (isIos ? CupertinoIcons.exclamationmark_triangle_fill : Icons.error),
                        color: controller.gstinValidationResult!.isValid ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.gstinValidationResult!.isValid
                              ? '${controller.gstinValidationResult!.details!.tradeName} • ${controller.gstinValidationResult!.details!.dealerType.displayName} (${controller.gstinValidationResult!.details!.stateName})'
                              : (controller.gstinValidationResult!.errorMessage ?? 'Invalid GSTIN'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: controller.gstinValidationResult!.isValid
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3b. Payment Mode & Settlement Card (Only for financial documents: Sales Invoice & Purchase)
        if (isSalesInvoice || isPurchase) ...[
          VoucherAdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.creditcard : Icons.payments_outlined,
                      size: 18,
                      color: accentColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Payment & Settlement Terms',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PaymentMode.values.map((mode) {
                    final isSelected = controller.selectedPaymentMode == mode;
                    return ChoiceChip(
                      label: Text(mode.displayName),
                      selected: isSelected,
                      selectedColor: accentColor.withValues(alpha: 0.18),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? accentColor : Theme.of(context).colorScheme.onSurface,
                      ),
                      onSelected: (selected) {
                        if (selected) controller.setPaymentMode(mode);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.selectedPaymentMode == PaymentMode.credit
                      ? (isSalesInvoice
                          ? 'Posts to Accounts Receivable (Customer Account Debit)'
                          : 'Posts to Accounts Payable (Supplier Account Credit)')
                      : 'Settles immediately via ${controller.selectedPaymentMode.displayName} Account',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 4. Consignee (Ship-To) Address Section
        if (isSalesInvoice || isSalesOrder) ...[
          VoucherAdaptiveCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Consignee (Ship-To) Address',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Switch.adaptive(
                      value: controller.isBillToShipToDifferent,
                      onChanged: controller.toggleBillToShipToDifferent,
                    ),
                  ],
                ),
                if (controller.isBillToShipToDifferent) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller.shipToAddressController,
                    decoration: InputDecoration(
                      labelText: 'Ship-To Delivery Address',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller.shipToGstinController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Ship-To GSTIN (or "URP" if unregistered)',
                      helperText: 'Statutory e-Way bill requirement: Enter valid GSTIN or type "URP"',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
