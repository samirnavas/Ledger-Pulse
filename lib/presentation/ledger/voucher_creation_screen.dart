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
import '../../data/models/inventory_item_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/gst_validation_service.dart';
import '../providers/company_providers.dart';
import '../providers/gst_providers.dart';
import '../providers/inventory_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/voucher_providers.dart';
import '../reports/invoice_pdf_generator.dart';
import '../reports/pdf_export_modal.dart';
import 'order_conversion_dialog.dart';

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
  ConsumerState<VoucherCreationScreen> createState() => _VoucherCreationScreenState();
}

class _VoucherCreationScreenState extends ConsumerState<VoucherCreationScreen> {
  late VoucherType _selectedType;
  DateTime _voucherDate = DateTime.now();
  DateTime? _dueDate;
  Party? _selectedParty;
  PaymentMode _selectedPaymentMode = PaymentMode.credit;

  final TextEditingController _voucherNumberController = TextEditingController();
  final TextEditingController _partyGstinController = TextEditingController();
  final TextEditingController _placeOfSupplyController = TextEditingController(text: '29');
  final TextEditingController _narrationController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _referenceNumberController = TextEditingController();

  bool get _isSalesOrder => _selectedType == VoucherType.salesOrder;
  bool get _isEstimate => _selectedType == VoucherType.estimate;

  // Bill-To / Ship-To State
  bool _isBillToShipToDifferent = false;
  final TextEditingController _shipToAddressController = TextEditingController();
  final TextEditingController _shipToGstinController = TextEditingController(text: 'URP');

  // GST Validation State
  bool _isValidatingGstin = false;
  GstValidationResult? _gstinValidationResult;

  // Items State (Starts empty)
  final List<VoucherItemModel> _items = [];

  // e-Invoice / e-Way Bill State
  EInvoiceDetails? _generatedEInvoice;
  EWayBillDetails? _generatedEWayBill;
  bool _isGeneratingEInvoice = false;
  bool _isGeneratingEWayBill = false;
  String? _complianceErrorMessage;
  bool _isSaving = false;

  // Drafting and Editing State
  String? _editingVoucherId;
  VoucherStatus _currentStatus = VoucherStatus.posted;
  String? _sourceVoucherId;
  VoucherModel? _loadedVoucher;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _selectedParty = widget.initialParty;
    _selectedPaymentMode = widget.initialParty != null ? PaymentMode.credit : PaymentMode.cash;

    if (widget.initialVoucher != null) {
      _loadVoucher(widget.initialVoucher!);
    } else {
      _voucherNumberController.text = '${_selectedType.prefix}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      _initializeDocumentNumber(_selectedType);

      if (_selectedParty != null) {
        if (_selectedParty!.gstin != null && _selectedParty!.gstin!.isNotEmpty) {
          _partyGstinController.text = _selectedParty!.gstin!;
        }
        if (_selectedParty!.stateCode != null && _selectedParty!.stateCode!.isNotEmpty) {
          _placeOfSupplyController.text = _selectedParty!.stateCode!;
        }
      }
    }
  }

  Future<void> _initializeDocumentNumber(VoucherType type) async {
    try {
      final repo = ref.read(voucherRepositoryProvider);
      final nextNumber = await repo.generateNextVoucherNumber(type);
      if (mounted && _editingVoucherId == null) {
        setState(() {
          _voucherNumberController.text = nextNumber;
        });
      }
    } catch (e) {
      debugPrint('Failed to initialize document number for $type: $e');
    }
  }

  void _onTypeChanged(VoucherType newType) {
    if (_selectedType == newType) return;
    HapticFeedback.selectionClick();

    setState(() {
      _selectedType = newType;

      // Party validation adjustment
      if (_selectedParty != null) {
        final isSupplierParty = _selectedParty!.type == PartyType.supplier;
        final isPurchaseType = newType == VoucherType.purchase;
        if (isPurchaseType && !isSupplierParty) {
          _selectedParty = null;
          _partyGstinController.clear();
        } else if (!isPurchaseType && isSupplierParty) {
          _selectedParty = null;
          _partyGstinController.clear();
        }
      }

      // Default status adjustment
      if (_editingVoucherId == null) {
        switch (newType) {
          case VoucherType.sales:
            _currentStatus = VoucherStatus.posted;
            break;
          case VoucherType.purchase:
            _currentStatus = VoucherStatus.posted;
            break;
          case VoucherType.salesOrder:
            _currentStatus = VoucherStatus.confirmed;
            break;
          case VoucherType.estimate:
            _currentStatus = VoucherStatus.draft;
            break;
          default:
            _currentStatus = VoucherStatus.posted;
        }
      }
    });

    if (_editingVoucherId == null) {
      _initializeDocumentNumber(newType);
    }
  }

  void _loadVoucher(VoucherModel v) {
    _loadedVoucher = v;
    setState(() {
      _editingVoucherId = v.id;
      _selectedType = v.type;
      _currentStatus = v.status;
      _selectedPaymentMode = v.paymentMode;
      _voucherDate = v.date;
      _dueDate = v.dueDate;
      _voucherNumberController.text = v.voucherNumber;
      _placeOfSupplyController.text = v.placeOfSupplyStateCode ?? '29';
      _narrationController.text = v.narration ?? '';
      _referenceNumberController.text = v.referenceNumber ?? '';
      _sourceVoucherId = v.sourceVoucherId;
      _discountController.text = (v.discountInCents / 100).toStringAsFixed(0);
      _items.clear();
      _items.addAll(v.items);
      _isBillToShipToDifferent = v.isBillToShipToDifferent;
      _shipToAddressController.text = v.shipToAddress ?? '';
      _shipToGstinController.text = v.shipToGstin ?? 'URP';
      _generatedEInvoice = v.irn != null
          ? EInvoiceDetails(
              irn: v.irn!,
              signedQrCode: v.signedQrCode ?? '',
              signedInvoice: '',
              ackNumber: '',
              ackDate: v.date,
            )
          : null;
      _generatedEWayBill = v.eWayBillNumber != null
          ? EWayBillDetails(
              eWayBillNumber: v.eWayBillNumber!,
              generatedDate: v.date,
              validUptoDate: v.date.add(const Duration(days: 3)),
              shipToGstinOrUrp: v.shipToGstin ?? 'URP',
            )
          : null;
    });

    if (v.partyId != null) {
      final parties = ref.read(partyListProvider).value ?? [];
      final match = parties.firstWhere(
        (p) => p.id == v.partyId,
        orElse: () => Party(
          id: v.partyId!,
          name: v.partyName ?? 'Party',
          phoneNumber: '',
          type: v.type == VoucherType.purchase ? PartyType.supplier : PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ),
      );
      setState(() {
        _selectedParty = match;
        if (match.gstin != null && match.gstin!.isNotEmpty) {
          _partyGstinController.text = match.gstin!;
        }
      });
    }
  }

  @override
  void dispose() {
    _voucherNumberController.dispose();
    _partyGstinController.dispose();
    _placeOfSupplyController.dispose();
    _narrationController.dispose();
    _discountController.dispose();
    _referenceNumberController.dispose();
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

  VoucherModel _buildVoucherModel(Company company, Party party, GstTaxBreakdown breakdown, {VoucherStatus? status}) {
    return VoucherModel(
      id: _editingVoucherId ?? 'vch_${DateTime.now().millisecondsSinceEpoch}',
      companyId: company.id,
      voucherNumber: _voucherNumberController.text.trim().isNotEmpty
          ? _voucherNumberController.text.trim()
          : '${_selectedType.prefix}-0001',
      type: _selectedType,
      date: _voucherDate,
      dueDate: _dueDate,
      partyId: party.id,
      partyName: party.name,
      status: status ?? _currentStatus,
      paymentMode: _selectedPaymentMode,
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
      referenceNumber: _referenceNumberController.text.trim().isNotEmpty ? _referenceNumberController.text.trim() : null,
      sourceVoucherId: _sourceVoucherId,
      createdAt: _loadedVoucher?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _showAddItemSelectorSheet({bool startWithService = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItemSelectorModal(
        voucherType: _selectedType,
        initialIsService: startWithService,
        onItemAdded: (item) {
          setState(() {
            _items.add(item);
          });
        },
      ),
    );
  }

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

  void _showEditItemQty(int index) {
    final item = _items[index];
    final qtyController = TextEditingController(text: item.quantity.toStringAsFixed(0));
    final rateController = TextEditingController(text: (item.unitPriceInCents / 100.0).toStringAsFixed(2));
    final isIos = AdaptiveThemeHelper.isIos(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Edit ${item.itemName}',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: qtyController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity (${item.unit})',
            prefixIcon: Icon(isIos ? CupertinoIcons.number : Icons.tag_rounded, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: rateController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Unit Rate (₹)',
            prefixIcon: Icon(isIos ? CupertinoIcons.money_dollar : Icons.currency_rupee_rounded, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            AdaptiveButton(
              type: AdaptiveButtonType.primary,
              height: 40,
              onPressed: () {
                final newQty = double.tryParse(qtyController.text) ?? item.quantity;
                final newRate = double.tryParse(rateController.text) ?? (item.unitPriceInCents / 100.0);
                final unitPriceCents = (newRate * 100).round();
                final grossCents = (unitPriceCents * newQty).round();
                final taxCents = ((grossCents * item.taxRatePercent) / 100.0).round();

                setState(() {
                  _items[index] = VoucherItemModel(
                    itemId: item.itemId,
                    itemName: item.itemName,
                    sku: item.sku,
                    hsnCode: item.hsnCode,
                    quantity: newQty,
                    unit: item.unit,
                    unitPriceInCents: unitPriceCents,
                    taxRatePercent: item.taxRatePercent,
                    discountInCents: item.discountInCents,
                    cgstInCents: item.cgstInCents,
                    sgstInCents: item.sgstInCents,
                    igstInCents: item.igstInCents,
                    totalInCents: grossCents + taxCents,
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('Update Item'),
            ),
          ],
        ),
      ],
    );

    if (isIos) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => LiquidGlassCard(
          borderRadius: 24,
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          padding: const EdgeInsets.all(20),
          color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.8) : CupertinoColors.systemBackground.withValues(alpha: 0.85),
          child: Material(
            type: MaterialType.transparency,
            child: content,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          content: content,
        ),
      );
    }
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
    final fileName = '${_selectedType.prefix}_${voucher.voucherNumber}.pdf';
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

  Future<void> _saveVoucher(Company company, Party party, {VoucherStatus status = VoucherStatus.posted}) async {
    final requiresItems = (status == VoucherStatus.posted || status == VoucherStatus.confirmed);
    if (_items.isEmpty && requiresItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one line item before saving')),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final breakdown = _calculateBreakdown(company);
      final voucher = _buildVoucherModel(company, party, breakdown, status: status);

      await ref.read(voucherControllerProvider.notifier).createVoucher(voucher);

      if (mounted) {
        String message;
        Color snackbarColor;

        if (status == VoucherStatus.draft) {
          message = '${voucher.type.displayName} Draft #${voucher.voucherNumber} saved!';
          snackbarColor = Colors.blueGrey;
        } else if (status == VoucherStatus.onHold) {
          message = '${voucher.type.displayName} #${voucher.voucherNumber} placed on hold!';
          snackbarColor = Colors.amber.shade800;
        } else if (voucher.type == VoucherType.salesOrder) {
          message = 'Sales Order #${voucher.voucherNumber} confirmed!';
          snackbarColor = AppColors.primaryBlue;
        } else if (voucher.type == VoucherType.estimate) {
          message = 'Quotation #${voucher.voucherNumber} saved successfully!';
          snackbarColor = Colors.deepPurple;
        } else if (voucher.type == VoucherType.purchase) {
          message = 'Purchase Bill #${voucher.voucherNumber} posted to Payables & Inventory!';
          snackbarColor = AppColors.payableRed;
        } else {
          message = 'Sales Invoice #${voucher.voucherNumber} posted to Receivables & Stock!';
          snackbarColor = AppColors.receivableGreen;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: snackbarColor,
          ),
        );
        Navigator.of(context).pop(voucher);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save document: $e'), backgroundColor: AppColors.payableRed),
        );
      }
    }
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
                      setState(() {
                        _editingVoucherId = null;
                        _loadedVoucher = null;
                        _currentStatus = VoucherStatus.posted;
                        _items.clear();
                      });
                      _initializeDocumentNumber(_selectedType);
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
                            const Text('No drafts or held documents found', style: TextStyle(color: Colors.grey)),
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          leading: CircleAvatar(
                            backgroundColor: isOnHold
                                ? Colors.amber.withValues(alpha: 0.2)
                                : Colors.blueGrey.withValues(alpha: 0.2),
                            child: Icon(
                              isOnHold
                                  ? (isIos ? CupertinoIcons.pause_fill : Icons.pause_circle_rounded)
                                  : (isIos ? CupertinoIcons.doc_text : Icons.drafts_rounded),
                              color: isOnHold ? Colors.amber.shade900 : Colors.blueGrey.shade800,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text('#${d.voucherNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOnHold ? Colors.amber.shade100 : Colors.blueGrey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isOnHold ? 'ON HOLD' : 'DRAFT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isOnHold ? Colors.amber.shade900 : Colors.blueGrey.shade900,
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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Text('Resume >', style: TextStyle(fontSize: 11, color: AppColors.primaryBlue)),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _loadVoucher(d);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Loaded ${isOnHold ? "held bill" : "draft"} #${d.voucherNumber}'),
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

  Color _getTypeAccentColor() {
    switch (_selectedType) {
      case VoucherType.sales:
        return AppColors.receivableGreen;
      case VoucherType.salesOrder:
        return AppColors.primaryBlue;
      case VoucherType.estimate:
        return Colors.deepPurple;
      case VoucherType.purchase:
        return AppColors.payableRed;
      default:
        return AppColors.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final company = ref.watch(activeCompanyProvider);
    final quota = ref.watch(subscriptionQuotaProvider);
    final partiesAsync = ref.watch(partyListProvider);

    final isPurchase = _selectedType == VoucherType.purchase;
    final isSalesOrder = _selectedType == VoucherType.salesOrder;
    final isEstimate = _selectedType == VoucherType.estimate;
    final isSalesInvoice = _selectedType == VoucherType.sales;

    final fallbackParty = _selectedParty ??
        Party(
          id: isPurchase ? 'pty_temp_supp' : 'pty_temp_cust',
          name: isPurchase ? 'Paramount Wholesale Suppliers' : 'Apex Infotech Solutions',
          phoneNumber: '+91 98765 43210',
          type: isPurchase ? PartyType.supplier : PartyType.customer,
          netBalanceInCents: 0,
          gstin: _partyGstinController.text.trim(),
          stateCode: _placeOfSupplyController.text.trim(),
          lastUpdated: DateTime.now(),
        );

    final activeParty = _selectedParty ?? fallbackParty;
    final breakdown = _calculateBreakdown(company);
    final accentColor = _getTypeAccentColor();

    return AdaptiveScaffold(
      title: _editingVoucherId != null
          ? 'Edit ${_currentStatus == VoucherStatus.onHold ? "Held Bill" : _currentStatus == VoucherStatus.draft ? "Draft" : _selectedType.displayName}'
          : 'New ${_selectedType.displayName}',
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
                  isIos ? CupertinoIcons.tray_full : Icons.folder_open_rounded,
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
            // Editing Banner
            if (_editingVoucherId != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _currentStatus == VoucherStatus.onHold
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.blueGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _currentStatus == VoucherStatus.onHold
                        ? Colors.amber.shade700
                        : Colors.blueGrey.shade400,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentStatus == VoucherStatus.onHold
                          ? (isIos ? CupertinoIcons.pause_circle_fill : Icons.pause_circle_rounded)
                          : (isIos ? CupertinoIcons.doc_text_fill : Icons.drafts_rounded),
                      color: _currentStatus == VoucherStatus.onHold
                          ? Colors.amber.shade900
                          : Colors.blueGrey.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Editing ${_selectedType.displayName} #${_voucherNumberController.text} (${_currentStatus.displayName})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _currentStatus == VoucherStatus.onHold
                              ? Colors.amber.shade900
                              : Colors.blueGrey.shade900,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _editingVoucherId = null;
                          _loadedVoucher = null;
                          _currentStatus = VoucherStatus.posted;
                        });
                        _initializeDocumentNumber(_selectedType);
                      },
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
              groupValue: _selectedType,
              children: const {
                VoucherType.sales: Text('Sales Invoice'),
                VoucherType.salesOrder: Text('Sales Order'),
                VoucherType.estimate: Text('Estimate / Quote'),
                VoucherType.purchase: Text('Purchase Bill'),
              },
              onValueChanged: _onTypeChanged,
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
                            initialDate: _voucherDate,
                            onDateSelected: (d) => setState(() => _voucherDate = d),
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
                            child: Text(DateFormatter.formatShortDate(_voucherDate)),
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
                            initialDate: _dueDate ?? _voucherDate.add(const Duration(days: 15)),
                            onDateSelected: (d) => setState(() => _dueDate = d),
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
                              suffixIcon: _dueDate != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () => setState(() => _dueDate = null),
                                    )
                                  : null,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              _dueDate != null ? DateFormatter.formatShortDate(_dueDate!) : 'Not specified',
                              style: TextStyle(
                                color: _dueDate != null
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
                          controller: _referenceNumberController,
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
                          controller: _placeOfSupplyController,
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
                            value: filteredParties.any((p) => p.id == _selectedParty?.id)
                                ? _selectedParty?.id
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
                                setState(() {
                                  _selectedParty = party;
                                  if (party.gstin != null) _partyGstinController.text = party.gstin!;
                                  if (party.stateCode != null) _placeOfSupplyController.text = party.stateCode!;
                                });
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
                          controller: _partyGstinController,
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
                            _gstinValidationResult!.isValid
                                ? (isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                                : (isIos ? CupertinoIcons.exclamationmark_triangle_fill : Icons.error),
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

            // 3b. Payment Mode & Settlement Card (Only for financial documents: Sales Invoice & Purchase)
            if (isSalesInvoice || isPurchase) ...[
              _buildAdaptiveCard(
                context: context,
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
                        final isSelected = _selectedPaymentMode == mode;
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
                            if (selected) setState(() => _selectedPaymentMode = mode);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedPaymentMode == PaymentMode.credit
                          ? (isSalesInvoice
                              ? 'Posts to Accounts Receivable (Customer Account Debit)'
                              : 'Posts to Accounts Payable (Supplier Account Credit)')
                          : 'Settles immediately via ${_selectedPaymentMode.displayName} Account',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 4. Consignee (Ship-To) Address Section
            if (isSalesInvoice || isSalesOrder) ...[
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
            ],

            // 5. Line Items List (Connected to Item Master)
            _buildAdaptiveCard(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Line Items (${_items.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Wrap(
                        spacing: 2,
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showAddItemSelectorSheet(startWithService: false),
                            icon: Icon(
                              isIos ? CupertinoIcons.cube_box : Icons.inventory_2_outlined,
                              size: 15,
                              color: accentColor,
                            ),
                            label: Text(
                              '+ Stock',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor),
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showAddItemSelectorSheet(startWithService: true),
                            icon: Icon(
                              isIos ? CupertinoIcons.bolt : Icons.miscellaneous_services_outlined,
                              size: 15,
                              color: Colors.deepPurple,
                            ),
                            label: const Text(
                              '+ Service',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  if (_items.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              isIos ? CupertinoIcons.cart_badge_plus : Icons.add_shopping_cart_rounded,
                              size: 38,
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No line items added yet',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isPurchase
                                  ? 'Select inventory goods from Item Master or add service lines.'
                                  : 'Select goods from Item Master inventory or add non-stock service lines.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showAddItemSelectorSheet(startWithService: false),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.inventory_2_rounded, size: 16),
                                  label: const Text('Add from Item Master', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _showAddItemSelectorSheet(startWithService: true),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.flash_on_rounded, size: 16, color: Colors.deepPurple),
                                  label: const Text('Add Service Line', style: TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ...List.generate(_items.length, (index) {
                      final item = _items[index];
                      final isService = item.itemId.startsWith('srv_');
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isService
                                        ? Colors.deepPurple.withValues(alpha: 0.12)
                                        : accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isService ? '⚡ Service' : '📦 Stock (${item.unit})',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isService ? Colors.deepPurple : accentColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.itemName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(item.totalInCents),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'HSN: ${item.hsnCode} • ₹${(item.unitPriceInCents / 100.0).toStringAsFixed(2)} • GST ${item.taxRatePercent.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Row(
                                  children: [
                                    // Quantity Stepper Controls
                                    InkWell(
                                      onTap: () {
                                        if (item.quantity > 1) {
                                          final newQty = item.quantity - 1;
                                          final unitPrice = item.unitPriceInCents;
                                          final gross = (unitPrice * newQty).round();
                                          final tax = ((gross * item.taxRatePercent) / 100.0).round();
                                          setState(() {
                                            _items[index] = VoucherItemModel(
                                              itemId: item.itemId,
                                              itemName: item.itemName,
                                              sku: item.sku,
                                              hsnCode: item.hsnCode,
                                              quantity: newQty,
                                              unit: item.unit,
                                              unitPriceInCents: unitPrice,
                                              taxRatePercent: item.taxRatePercent,
                                              discountInCents: item.discountInCents,
                                              cgstInCents: item.cgstInCents,
                                              sgstInCents: item.sgstInCents,
                                              igstInCents: item.igstInCents,
                                              totalInCents: gross + tax,
                                            );
                                          });
                                        } else {
                                          setState(() => _items.removeAt(index));
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade400),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.remove, size: 14),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => _showEditItemQty(index),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(
                                          '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        final newQty = item.quantity + 1;
                                        final unitPrice = item.unitPriceInCents;
                                        final gross = (unitPrice * newQty).round();
                                        final tax = ((gross * item.taxRatePercent) / 100.0).round();
                                        setState(() {
                                          _items[index] = VoucherItemModel(
                                            itemId: item.itemId,
                                            itemName: item.itemName,
                                            sku: item.sku,
                                            hsnCode: item.hsnCode,
                                            quantity: newQty,
                                            unit: item.unit,
                                            unitPriceInCents: unitPrice,
                                            taxRatePercent: item.taxRatePercent,
                                            discountInCents: item.discountInCents,
                                            cgstInCents: item.cgstInCents,
                                            sgstInCents: item.sgstInCents,
                                            igstInCents: item.igstInCents,
                                            totalInCents: gross + tax,
                                          );
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade400),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.add, size: 14),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      onPressed: () => setState(() => _items.removeAt(index)),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
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
                                        _generatedEInvoice != null
                                            ? (isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                                            : (isIos ? CupertinoIcons.qrcode : Icons.qr_code_2_rounded),
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
                                        _generatedEWayBill != null
                                            ? (isIos ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                                            : (isIos ? CupertinoIcons.bus : Icons.local_shipping_rounded),
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
              const SizedBox(height: 16),
            ],

            // 7b. Conversion Card if editing an existing Estimate or Sales Order
            if (_loadedVoucher != null && (_isEstimate || _isSalesOrder) && _currentStatus != VoucherStatus.converted) ...[
              _buildAdaptiveCard(
                context: context,
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
                      _isEstimate
                          ? 'Convert this Quotation into a confirmed Sales Order or a posted Sales Invoice.'
                          : 'Convert this confirmed Sales Order into a posted Sales Invoice.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_isEstimate) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => OrderConversionDialog.show(context, _loadedVoucher!),
                              icon: const Icon(Icons.assignment_outlined, size: 16),
                              label: const Text('Convert Options', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => OrderConversionDialog.show(context, _loadedVoucher!),
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
                    onPressed: _isSaving ? null : () => _saveVoucher(company, activeParty, status: VoucherStatus.draft),
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
                      onPressed: _isSaving ? null : () => _saveVoucher(company, activeParty, status: VoucherStatus.onHold),
                      icon: Icon(
                        isIos ? CupertinoIcons.pause_circle : Icons.pause_circle_outline_rounded,
                        size: 16,
                        color: Colors.amber.shade800,
                      ),
                      label: Text(
                        'Hold Bill',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.amber.shade900),
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
                    onPressed: () => _previewAndExportPdf(company, activeParty),
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
                    onPressed: _isSaving
                        ? () {}
                        : () => _saveVoucher(
                              company,
                              activeParty,
                              status: isSalesOrder
                                  ? VoucherStatus.confirmed
                                  : isEstimate
                                      ? VoucherStatus.posted
                                      : VoucherStatus.posted,
                            ),
                    type: AdaptiveButtonType.primary,
                    height: 52,
                    child: _isSaving
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
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.7),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.08),
        child: child,
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        child: child,
      );
    }
  }
}

class _ItemSelectorModal extends ConsumerStatefulWidget {
  final VoucherType voucherType;
  final bool initialIsService;
  final ValueChanged<VoucherItemModel> onItemAdded;

  const _ItemSelectorModal({
    required this.voucherType,
    this.initialIsService = false,
    required this.onItemAdded,
  });

  @override
  ConsumerState<_ItemSelectorModal> createState() => _ItemSelectorModalState();
}

class _ItemSelectorModalState extends ConsumerState<_ItemSelectorModal> {
  late bool _isServiceMode;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Selected Inventory Item config state
  InventoryItem? _selectedItem;
  final TextEditingController _itemQtyController = TextEditingController(text: '1');
  final TextEditingController _itemRateController = TextEditingController();
  final TextEditingController _itemTaxRateController = TextEditingController(text: '18');
  final TextEditingController _itemHsnController = TextEditingController();

  // Service Line form state
  final TextEditingController _serviceNameController = TextEditingController();
  final TextEditingController _serviceHsnController = TextEditingController(text: '9983');
  final TextEditingController _serviceQtyController = TextEditingController(text: '1');
  final TextEditingController _serviceUnitController = TextEditingController(text: 'HRS');
  final TextEditingController _serviceRateController = TextEditingController(text: '1000');
  final TextEditingController _serviceTaxRateController = TextEditingController(text: '18');

  @override
  void initState() {
    super.initState();
    _isServiceMode = widget.initialIsService;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _itemQtyController.dispose();
    _itemRateController.dispose();
    _itemTaxRateController.dispose();
    _itemHsnController.dispose();
    _serviceNameController.dispose();
    _serviceHsnController.dispose();
    _serviceQtyController.dispose();
    _serviceUnitController.dispose();
    _serviceRateController.dispose();
    _serviceTaxRateController.dispose();
    super.dispose();
  }

  void _selectInventoryItem(InventoryItem item) {
    setState(() {
      _selectedItem = item;
      _itemQtyController.text = '1';
      final price = widget.voucherType == VoucherType.purchase
          ? (item.purchasePriceInCents > 0 ? item.purchasePriceInCents : item.sellingPriceInCents)
          : item.sellingPriceInCents;
      _itemRateController.text = (price / 100.0).toStringAsFixed(2);
      _itemTaxRateController.text = item.taxRatePercent.toStringAsFixed(0);
      _itemHsnController.text = item.hsnCode ?? '';
    });
  }

  void _addSelectedItemToInvoice() {
    if (_selectedItem == null) return;
    final qty = double.tryParse(_itemQtyController.text) ?? 1.0;
    final defaultPrice = widget.voucherType == VoucherType.purchase
        ? (_selectedItem!.purchasePriceInCents > 0 ? _selectedItem!.purchasePriceInCents : _selectedItem!.sellingPriceInCents)
        : _selectedItem!.sellingPriceInCents;
    final rate = double.tryParse(_itemRateController.text) ?? (defaultPrice / 100.0);
    final taxRate = double.tryParse(_itemTaxRateController.text) ?? _selectedItem!.taxRatePercent;
    final unitPriceCents = (rate * 100).round();
    final grossCents = (unitPriceCents * qty).round();
    final taxCents = ((grossCents * taxRate) / 100.0).round();

    final voucherItem = VoucherItemModel(
      itemId: _selectedItem!.id,
      itemName: _selectedItem!.name,
      sku: _selectedItem!.sku.isNotEmpty
          ? _selectedItem!.sku
          : 'SKU-${_selectedItem!.name.substring(0, _selectedItem!.name.length.clamp(1, 3)).toUpperCase()}',
      hsnCode: _itemHsnController.text.trim().isNotEmpty ? _itemHsnController.text.trim() : (_selectedItem!.hsnCode ?? ''),
      quantity: qty,
      unit: _selectedItem!.unit,
      unitPriceInCents: unitPriceCents,
      taxRatePercent: taxRate,
      totalInCents: grossCents + taxCents,
    );

    widget.onItemAdded(voucherItem);
    Navigator.of(context).pop();
  }

  void _addServiceLineToInvoice() {
    final name = _serviceNameController.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(_serviceQtyController.text) ?? 1.0;
    final rate = double.tryParse(_serviceRateController.text) ?? 0.0;
    final taxRate = double.tryParse(_serviceTaxRateController.text) ?? 18.0;
    final unit = _serviceUnitController.text.trim().isNotEmpty ? _serviceUnitController.text.trim() : 'HRS';
    final unitPriceCents = (rate * 100).round();
    final grossCents = (unitPriceCents * qty).round();
    final taxCents = ((grossCents * taxRate) / 100.0).round();

    final voucherItem = VoucherItemModel(
      itemId: 'srv_${DateTime.now().millisecondsSinceEpoch}',
      itemName: name,
      sku: 'SRV-${name.substring(0, name.length.clamp(1, 3)).toUpperCase()}',
      hsnCode: _serviceHsnController.text.trim(),
      quantity: qty,
      unit: unit,
      unitPriceInCents: unitPriceCents,
      taxRatePercent: taxRate,
      totalInCents: grossCents + taxCents,
    );

    widget.onItemAdded(voucherItem);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryItemsListProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (ctx, scrollController) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            decoration: BoxDecoration(
              color: isIos
                  ? CupertinoColors.systemBackground.resolveFrom(context)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isIos ? CupertinoColors.systemGrey4 : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add Line Item',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: isIos ? -0.4 : 0,
                    color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: Icon(isIos ? CupertinoIcons.xmark : Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tab Selector
            AdaptiveSegmentedControl<bool>(
              groupValue: _isServiceMode,
              children: const {
                false: Text('📦 Item Master (Stock)'),
                true: Text('⚡ Service (Non-Stock)'),
              },
              onValueChanged: (val) {
                setState(() {
                  _isServiceMode = val;
                  _selectedItem = null;
                });
              },
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _isServiceMode
                  ? _buildServiceForm()
                  : _selectedItem != null
                      ? _buildItemCustomizer()
                      : _buildInventoryList(itemsAsync, scrollController, isIos),
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildInventoryList(AsyncValue<List<InventoryItem>> itemsAsync, ScrollController scroll, bool isIos) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search items by name, SKU, HSN...',
            prefixIcon: Icon(isIos ? CupertinoIcons.search : Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(isIos ? CupertinoIcons.clear_circled_solid : Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                  )
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              final filtered = items.where((item) {
                if (_searchQuery.isEmpty) return true;
                final nameMatch = item.name.toLowerCase().contains(_searchQuery);
                final skuMatch = item.sku.toLowerCase().contains(_searchQuery);
                final hsnMatch = item.hsnCode?.toLowerCase().contains(_searchQuery) ?? false;
                return nameMatch || skuMatch || hsnMatch;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isIos ? CupertinoIcons.cube_box : Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isEmpty ? 'No inventory items in Item Master' : 'No items matching "$_searchQuery"',
                        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Add items in the Inventory screen or add as a Service Line.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                controller: scroll,
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final item = filtered[index];
                  final priceCents = widget.voucherType == VoucherType.purchase
                      ? (item.purchasePriceInCents > 0 ? item.purchasePriceInCents : item.sellingPriceInCents)
                      : item.sellingPriceInCents;
                  final stockColor = item.currentStockQuantity > 5
                      ? AppColors.receivableGreen
                      : item.currentStockQuantity > 0
                          ? Colors.amber.shade800
                          : Colors.red;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                      child: Text(
                        item.name.substring(0, item.name.length.clamp(1, 2)).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlue, fontSize: 13),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Text(
                          '₹${(priceCents / 100.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          'SKU: ${item.sku.isNotEmpty ? item.sku : "-"} • HSN: ${item.hsnCode ?? "-"} • GST ${item.taxRatePercent.toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit} in stock',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: stockColor),
                          ),
                        ),
                      ],
                    ),
                    trailing: Icon(isIos ? CupertinoIcons.chevron_right : Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                    onTap: () => _selectInventoryItem(item),
                  );
                },
              );
            },
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (err, _) => Center(child: Text('Error loading inventory: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCustomizer() {
    final item = _selectedItem!;
    final qty = double.tryParse(_itemQtyController.text) ?? 1.0;
    final defaultPrice = widget.voucherType == VoucherType.purchase
        ? (item.purchasePriceInCents > 0 ? item.purchasePriceInCents : item.sellingPriceInCents)
        : item.sellingPriceInCents;
    final rate = double.tryParse(_itemRateController.text) ?? (defaultPrice / 100.0);
    final taxRate = double.tryParse(_itemTaxRateController.text) ?? item.taxRatePercent;
    final totalCents = ((rate * 100 * qty) * (1 + (taxRate / 100.0))).round();
    final isIos = AdaptiveThemeHelper.isIos(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(isIos ? CupertinoIcons.back : Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selectedItem = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      'SKU: ${item.sku.isNotEmpty ? item.sku : "-"} • Stock: ${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemQtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quantity (${item.unit})',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _itemRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: widget.voucherType == VoucherType.purchase ? 'Purchase Rate (₹)' : 'Selling Rate (₹)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemHsnController,
                  decoration: const InputDecoration(
                    labelText: 'HSN / SAC Code',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _itemTaxRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'GST Rate %',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Line Amount (incl. GST):', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  CurrencyFormatter.format(totalCents),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.receivableGreen),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AdaptiveButton(
            onPressed: _addSelectedItemToInvoice,
            type: AdaptiveButtonType.primary,
            child: Text('Add to ${widget.voucherType.displayName}'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceForm() {
    final qty = double.tryParse(_serviceQtyController.text) ?? 1.0;
    final rate = double.tryParse(_serviceRateController.text) ?? 0.0;
    final taxRate = double.tryParse(_serviceTaxRateController.text) ?? 18.0;
    final totalCents = ((rate * 100 * qty) * (1 + (taxRate / 100.0))).round();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _serviceNameController,
            decoration: const InputDecoration(
              labelText: 'Service Name / Description',
              hintText: 'e.g. Legal Consulting, Software Maintenance',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serviceHsnController,
                  decoration: const InputDecoration(
                    labelText: 'SAC / HSN Code',
                    hintText: '9983',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit (e.g. HRS, NOS, JOB)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serviceQtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantity / Hours',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Unit Rate (₹)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceTaxRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'GST Rate %',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Service Amount (incl. GST):', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  CurrencyFormatter.format(totalCents),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AdaptiveButton(
            onPressed: _addServiceLineToInvoice,
            type: AdaptiveButtonType.primary,
            child: Text('Add Service Line to ${widget.voucherType.displayName}'),
          ),
        ],
      ),
    );
  }
}
