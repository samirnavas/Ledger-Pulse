import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/accounting/gst_tax_engine.dart';
import '../../data/models/company_model.dart';
import '../../data/models/gst_models.dart';
import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/gst_validation_service.dart';
import '../providers/company_providers.dart';
import '../providers/gst_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/voucher_providers.dart';
import '../reports/invoice_pdf_generator.dart';
import '../reports/pdf_export_modal.dart';

class VoucherCreationScreen extends ConsumerStatefulWidget {
  final Party? initialParty;
  final VoucherType initialType;

  const VoucherCreationScreen({
    super.key,
    this.initialParty,
    this.initialType = VoucherType.sales,
  });

  @override
  ConsumerState<VoucherCreationScreen> createState() => _VoucherCreationScreenState();
}

class _VoucherCreationScreenState extends ConsumerState<VoucherCreationScreen> {
  late VoucherType _selectedType;
  DateTime _voucherDate = DateTime.now();
  DateTime? _dueDate;
  Party? _selectedParty;

  final TextEditingController _voucherNumberController = TextEditingController();
  final TextEditingController _partyGstinController = TextEditingController();
  final TextEditingController _placeOfSupplyController = TextEditingController(text: '29');
  final TextEditingController _narrationController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(text: '0');

  // Bill-To / Ship-To State
  bool _isBillToShipToDifferent = false;
  final TextEditingController _shipToAddressController = TextEditingController();
  final TextEditingController _shipToGstinController = TextEditingController(text: 'URP');

  // GST Validation State
  bool _isValidatingGstin = false;
  GstValidationResult? _gstinValidationResult;

  // Items State
  final List<VoucherItemModel> _items = [];

  // e-Invoice / e-Way Bill State
  EInvoiceDetails? _generatedEInvoice;
  EWayBillDetails? _generatedEWayBill;
  bool _isGeneratingEInvoice = false;
  bool _isGeneratingEWayBill = false;
  String? _complianceErrorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _selectedParty = widget.initialParty;
    _voucherNumberController.text = 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    if (_selectedParty != null) {
      if (_selectedParty!.gstin != null && _selectedParty!.gstin!.isNotEmpty) {
        _partyGstinController.text = _selectedParty!.gstin!;
      }
      if (_selectedParty!.stateCode != null && _selectedParty!.stateCode!.isNotEmpty) {
        _placeOfSupplyController.text = _selectedParty!.stateCode!;
      }
    }

    // Add a default sample item to immediately showcase the tax calculation engine
    _items.add(
      const VoucherItemModel(
        itemId: 'item_sample_01',
        itemName: 'Enterprise Cloud ERP Consulting',
        sku: 'SRV-ERP-01',
        hsnCode: '998313',
        quantity: 1.0,
        unit: 'HRS',
        unitPriceInCents: 500000, // ₹5,000.00
        taxRatePercent: 18.0,
        totalInCents: 590000,
      ),
    );
  }

  @override
  void dispose() {
    _voucherNumberController.dispose();
    _partyGstinController.dispose();
    _placeOfSupplyController.dispose();
    _narrationController.dispose();
    _discountController.dispose();
    _shipToAddressController.dispose();
    _shipToGstinController.dispose();
    super.dispose();
  }

  Future<void> _validateGstin() async {
    final gstin = _partyGstinController.text.trim();
    if (gstin.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isValidatingGstin = true;
      _gstinValidationResult = null;
    });

    final validator = ref.read(gstValidationServiceProvider);
    final result = await validator.searchGstin(gstin);

    if (mounted) {
      setState(() {
        _isValidatingGstin = false;
        _gstinValidationResult = result;
        if (result.isValid && result.details != null) {
          _placeOfSupplyController.text = result.details!.stateCode;
        }
      });
    }
  }

  GstTaxBreakdown _calculateBreakdown(Company company) {
    final supplierState = company.stateCode ??
        (company.gstin != null && company.gstin!.length >= 2 ? company.gstin!.substring(0, 2) : '29');
    final supplierType = company.dealerType == 'composition'
        ? GstDealerType.composition
        : GstDealerType.regular;
    final pos = _placeOfSupplyController.text.trim().isNotEmpty
        ? _placeOfSupplyController.text.trim()
        : '29';
    final discountCents = ((double.tryParse(_discountController.text) ?? 0.0) * 100).toInt();

    return GstTaxEngine.calculateTax(
      supplierStateCode: supplierState,
      supplierDealerType: supplierType,
      placeOfSupplyStateCode: pos,
      items: _items,
      discountInCents: discountCents,
    );
  }

  Future<void> _generateEInvoice(Company company, Party party) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isGeneratingEInvoice = true;
      _complianceErrorMessage = null;
    });

    final service = ref.read(einvoiceEwaybillServiceProvider);
    final breakdown = _calculateBreakdown(company);

    final voucher = _buildVoucherModel(company, party, breakdown);

    final supplierGstin = company.gstin ?? '29ABCDE1234F1ZH';
    final buyerGstin = _partyGstinController.text.trim().isNotEmpty
        ? _partyGstinController.text.trim()
        : '29XYZDE9876K1Z2';

    final result = await service.generateEInvoice(
      voucher: voucher,
      supplierGstin: supplierGstin,
      buyerGstin: buyerGstin,
    );

    if (mounted) {
      setState(() {
        _isGeneratingEInvoice = false;
        if (result.success && result.details != null) {
          _generatedEInvoice = result.details;
          ref.read(subscriptionQuotaProvider.notifier).updateQuota(result.updatedQuota);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('e-Invoice IRN Generated: ${result.details!.irn.substring(0, 16)}...'),
              backgroundColor: AppColors.receivableGreen,
            ),
          );
        } else {
          _complianceErrorMessage = result.errorMessage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Failed to generate e-Invoice'),
              backgroundColor: AppColors.payableRed,
            ),
          );
        }
      });
    }
  }

  Future<void> _generateEWayBill(Company company, Party party) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isGeneratingEWayBill = true;
      _complianceErrorMessage = null;
    });

    final service = ref.read(einvoiceEwaybillServiceProvider);
    final breakdown = _calculateBreakdown(company);
    final voucher = _buildVoucherModel(company, party, breakdown);
    final supplierGstin = company.gstin ?? '29ABCDE1234F1ZH';

    final result = await service.generateEWayBill(
      voucher: voucher,
      supplierGstin: supplierGstin,
      isBillToShipToDifferent: _isBillToShipToDifferent,
      shipToGstinOrUrp: _shipToGstinController.text.trim(),
      vehicleNumber: 'KA-01-MJ-5501',
      distanceKm: 180.0,
    );

    if (mounted) {
      setState(() {
        _isGeneratingEWayBill = false;
        if (result.success && result.details != null) {
          _generatedEWayBill = result.details;
          ref.read(subscriptionQuotaProvider.notifier).updateQuota(result.updatedQuota);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('e-Way Bill Generated: ${result.details!.eWayBillNumber}'),
              backgroundColor: AppColors.receivableGreen,
            ),
          );
        } else {
          _complianceErrorMessage = result.errorMessage;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Failed to generate e-Way Bill'),
              backgroundColor: AppColors.payableRed,
            ),
          );
        }
      });
    }
  }

  VoucherModel _buildVoucherModel(Company company, Party party, GstTaxBreakdown breakdown) {
    return VoucherModel(
      id: 'vch_${DateTime.now().millisecondsSinceEpoch}',
      companyId: company.id,
      voucherNumber: _voucherNumberController.text.trim().isNotEmpty
          ? _voucherNumberController.text.trim()
          : 'INV-001',
      type: _selectedType,
      date: _voucherDate,
      dueDate: _dueDate,
      partyId: party.id,
      partyName: party.name,
      status: VoucherStatus.posted,
      items: _items,
      subtotalInCents: breakdown.subtotalInCents,
      taxInCents: breakdown.totalTaxInCents,
      cgstInCents: breakdown.cgstInCents,
      sgstInCents: breakdown.sgstInCents,
      igstInCents: breakdown.igstInCents,
      discountInCents: breakdown.discountInCents,
      totalAmountInCents: breakdown.totalAmountInCents,
      placeOfSupplyStateCode: _placeOfSupplyController.text.trim(),
      irn: _generatedEInvoice?.irn,
      signedQrCode: _generatedEInvoice?.signedQrCode,
      eWayBillNumber: _generatedEWayBill?.eWayBillNumber,
      shipToAddress: _isBillToShipToDifferent ? _shipToAddressController.text.trim() : null,
      shipToGstin: _isBillToShipToDifferent ? _shipToGstinController.text.trim() : null,
      isBillToShipToDifferent: _isBillToShipToDifferent,
      narration: _narrationController.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _previewAndExportPdf(Company company, Party party) async {
    HapticFeedback.lightImpact();
    final breakdown = _calculateBreakdown(company);
    final voucher = _buildVoucherModel(company, party, breakdown);

    final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
      voucher: voucher,
      company: company,
      party: party,
      templateType: InvoiceTemplateType.gstStatutory,
    );

    final tempDir = await getTemporaryDirectory();
    final fileName = 'Invoice_${voucher.voucherNumber}.pdf';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(pdfBytes);

    if (mounted) {
      PdfExportModal.show(
        context: context,
        pdfBytes: pdfBytes,
        file: file,
        fileName: fileName,
        partyName: party.name,
        periodLabel: DateFormatter.formatShortDate(voucher.date),
        partyPhone: party.phoneNumber,
        voucher: voucher,
        company: company,
        party: party,
      );
    }
  }

  Future<void> _saveVoucher(Company company, Party party) async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one line item')),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final breakdown = _calculateBreakdown(company);
      final voucher = _buildVoucherModel(company, party, breakdown);

      await ref.read(voucherControllerProvider.notifier).createVoucher(voucher);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voucher #${voucher.voucherNumber} created & posted!'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
        Navigator.of(context).pop(voucher);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save voucher: $e'), backgroundColor: AppColors.payableRed),
        );
      }
    }
  }

  void _showAddItemDialog() {
    final nameController = TextEditingController();
    final hsnController = TextEditingController(text: '9983');
    final qtyController = TextEditingController(text: '1');
    final rateController = TextEditingController(text: '1000');
    final taxRateController = TextEditingController(text: '18');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scroll,
            children: [
              ModalDragHandle(margin: const EdgeInsets.only(bottom: 12)),
              Text(
                'Add Line Item',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Item Name / Description', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hsnController,
                      decoration: const InputDecoration(labelText: 'HSN / SAC Code', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Unit Rate (₹)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: taxRateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'GST Rate %', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AdaptiveButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final qty = double.tryParse(qtyController.text) ?? 1.0;
                  final rate = (double.tryParse(rateController.text) ?? 0.0);
                  final taxRate = double.tryParse(taxRateController.text) ?? 18.0;
                  final unitPriceCents = (rate * 100).toInt();
                  final grossCents = (unitPriceCents * qty).round();
                  final taxCents = ((grossCents * taxRate) / 100.0).round();

                  setState(() {
                    _items.add(
                      VoucherItemModel(
                        itemId: 'item_${DateTime.now().millisecondsSinceEpoch}',
                        itemName: name,
                        sku: 'SKU-${name.substring(0, name.length.clamp(1, 3)).toUpperCase()}',
                        hsnCode: hsnController.text.trim(),
                        quantity: qty,
                        unit: 'PCS',
                        unitPriceInCents: unitPriceCents,
                        taxRatePercent: taxRate,
                        totalInCents: grossCents + taxCents,
                      ),
                    );
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Add Item to Voucher'),
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
    final quota = ref.watch(subscriptionQuotaProvider);
    final partiesAsync = ref.watch(partyListProvider);

    final fallbackParty = _selectedParty ??
        Party(
          id: 'pty_temp',
          name: 'Apex Infotech Solutions',
          phoneNumber: '+91 98765 43210',
          type: PartyType.customer,
          netBalanceInCents: 0,
          gstin: _partyGstinController.text.trim(),
          stateCode: _placeOfSupplyController.text.trim(),
          lastUpdated: DateTime.now(),
        );

    final activeParty = _selectedParty ?? fallbackParty;
    final breakdown = _calculateBreakdown(company);

    return AdaptiveScaffold(
      title: 'New ${voucherTypeTitle(_selectedType)}',
      actions: [
        IconButton(
          tooltip: 'Preview PDF Document',
          icon: Icon(
            isIos ? CupertinoIcons.doc_text_viewfinder : Icons.picture_as_pdf_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () => _previewAndExportPdf(company, activeParty),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Voucher Type Segmented Control
            AdaptiveSegmentedControl<VoucherType>(
              groupValue: _selectedType,
              children: const {
                VoucherType.sales: Text('Sales Invoice'),
                VoucherType.salesOrder: Text('Sales Order'),
                VoucherType.estimate: Text('Estimate'),
                VoucherType.purchase: Text('Purchase'),
              },
              onValueChanged: (type) => setState(() => _selectedType = type),
            ),
            const SizedBox(height: 16),

            // 2. Adaptive Header Card (Invoice No, Dates)
            _buildAdaptiveCard(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _voucherNumberController,
                          decoration: InputDecoration(
                            labelText: 'Document #',
                            isDense: true,
                            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _voucherDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) setState(() => _voucherDate = picked);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Date',
                              isDense: true,
                              prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(DateFormatter.formatShortDate(_voucherDate)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Place of supply input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _placeOfSupplyController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Place of Supply (State Code)',
                            hintText: 'e.g. 29 (Karnataka), 27 (Maharashtra)',
                            isDense: true,
                            prefixIcon: const Icon(Icons.location_on_rounded, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setState(() {}),
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
            _buildAdaptiveCard(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Party & GSTIN Details',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      partiesAsync.when(
                        data: (parties) => DropdownButton<String>(
                          value: _selectedParty?.id,
                          hint: const Text('Select Party', style: TextStyle(fontSize: 13)),
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: parties.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                          onChanged: (id) {
                            if (id != null) {
                              final party = parties.firstWhere((p) => p.id == id);
                              setState(() {
                                _selectedParty = party;
                                if (party.gstin != null) _partyGstinController.text = party.gstin!;
                                if (party.stateCode != null) _placeOfSupplyController.text = party.stateCode!;
                              });
                            }
                          },
                        ),
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
                          controller: _partyGstinController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Party GSTIN',
                            hintText: '15-digit alphanumeric',
                            isDense: true,
                            prefixIcon: const Icon(Icons.verified_user_rounded, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isValidatingGstin
                          ? const CupertinoActivityIndicator(radius: 12)
                          : AdaptiveButton(
                              onPressed: _validateGstin,
                              type: AdaptiveButtonType.secondary,
                              height: 48,
                              child: const Text('Verify'),
                            ),
                    ],
                  ),
                  if (_gstinValidationResult != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _gstinValidationResult!.isValid
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _gstinValidationResult!.isValid ? Icons.check_circle : Icons.error,
                            color: _gstinValidationResult!.isValid ? Colors.green : Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _gstinValidationResult!.isValid
                                  ? '${_gstinValidationResult!.details!.tradeName} • ${_gstinValidationResult!.details!.dealerType.displayName} (${_gstinValidationResult!.details!.stateName})'
                                  : (_gstinValidationResult!.errorMessage ?? 'Invalid GSTIN'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _gstinValidationResult!.isValid ? Colors.green.shade800 : Colors.red.shade800,
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

            // 4. Bill-To / Ship-To Consignee Section (with URP enforcement)
            _buildAdaptiveCard(
              context: context,
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
                        value: _isBillToShipToDifferent,
                        onChanged: (val) => setState(() => _isBillToShipToDifferent = val),
                      ),
                    ],
                  ),
                  if (_isBillToShipToDifferent) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _shipToAddressController,
                      decoration: InputDecoration(
                        labelText: 'Ship-To Delivery Address',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _shipToGstinController,
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

            // 5. Line Items List
            _buildAdaptiveCard(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Line Items (${_items.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      IconButton(
                        tooltip: 'Add Line Item',
                        icon: const Icon(Icons.add_circle_rounded, color: AppColors.primaryBlue),
                        onPressed: _showAddItemDialog,
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  ...List.generate(_items.length, (index) {
                    final item = _items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                Text(
                                  'HSN: ${item.hsnCode} • ${item.quantity.toStringAsFixed(0)} ${item.unit} @ ₹${(item.unitPriceInCents / 100.0).toStringAsFixed(2)} • GST ${item.taxRatePercent.toStringAsFixed(0)}%',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            CurrencyFormatter.format(item.totalInCents),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                            onPressed: () => setState(() => _items.removeAt(index)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 6. Real-time Tax Breakdown Card
            _buildAdaptiveCard(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tax Computation Summary',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                      const Text('Total Invoice Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        CurrencyFormatter.format(breakdown.totalAmountInCents),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.receivableGreen),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 7. e-Invoice & e-Way Bill Government Portal Integration Card
            _buildAdaptiveCard(
              context: context,
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
                  if (_complianceErrorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _complianceErrorMessage!,
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
                          onPressed: _isGeneratingEInvoice ? () {} : () => _generateEInvoice(company, activeParty),
                          type: _generatedEInvoice != null ? AdaptiveButtonType.secondary : AdaptiveButtonType.primary,
                          height: 44,
                          child: _isGeneratingEInvoice
                              ? const CupertinoActivityIndicator(radius: 10)
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _generatedEInvoice != null ? Icons.check_circle : Icons.qr_code_2_rounded,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _generatedEInvoice != null ? 'IRN Generated' : 'Generate IRN',
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
                          onPressed: _isGeneratingEWayBill ? () {} : () => _generateEWayBill(company, activeParty),
                          type: _generatedEWayBill != null ? AdaptiveButtonType.secondary : AdaptiveButtonType.primary,
                          height: 44,
                          child: _isGeneratingEWayBill
                              ? const CupertinoActivityIndicator(radius: 10)
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _generatedEWayBill != null ? Icons.check_circle : Icons.local_shipping_rounded,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _generatedEWayBill != null ? 'e-Way Active' : 'e-Way Bill',
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
            const SizedBox(height: 24),

            // 8. Main Action Buttons: Save & Generate Document
            Row(
              children: [
                Expanded(
                  child: AdaptiveButton(
                    onPressed: () => _previewAndExportPdf(company, activeParty),
                    type: AdaptiveButtonType.secondary,
                    height: 52,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('Preview PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AdaptiveButton(
                    onPressed: _isSaving ? () {} : () => _saveVoucher(company, activeParty),
                    type: AdaptiveButtonType.primary,
                    height: 52,
                    child: _isSaving
                        ? const CupertinoActivityIndicator(radius: 12, color: Colors.white)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 20, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Post Voucher', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

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

  Widget _buildAdaptiveCard({required BuildContext context, required Widget child}) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 20,
        padding: const EdgeInsets.all(16),
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.7),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
        child: child,
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
    }
  }

  String voucherTypeTitle(VoucherType type) {
    switch (type) {
      case VoucherType.sales:
        return 'Sales Invoice';
      case VoucherType.purchase:
        return 'Purchase Invoice';
      case VoucherType.salesOrder:
        return 'Sales Order';
      case VoucherType.purchaseOrder:
        return 'Purchase Order';
      case VoucherType.estimate:
        return 'Estimate / Quotation';
      default:
        return 'Voucher';
    }
  }
}
