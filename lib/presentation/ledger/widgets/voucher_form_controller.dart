import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/accounting/gst_tax_engine.dart';
import '../../../data/models/company_model.dart';
import '../../../data/models/gst_models.dart';
import '../../../data/models/party_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/services/gst_validation_service.dart';
import '../../providers/gst_providers.dart';
import '../../providers/ledger_providers.dart';
import '../../providers/voucher_providers.dart';
import '../reports/invoice_pdf_generator.dart';
import '../reports/pdf_export_modal.dart';

/// Form state controller and logic notifier for VoucherCreationScreen.
class VoucherFormController extends ChangeNotifier {
  final WidgetRef ref;

  VoucherType _selectedType;
  DateTime _voucherDate = DateTime.now();
  DateTime? _dueDate;
  Party? _selectedParty;
  PaymentMode _selectedPaymentMode = PaymentMode.credit;

  final TextEditingController voucherNumberController = TextEditingController();
  final TextEditingController partyGstinController = TextEditingController();
  final TextEditingController placeOfSupplyController = TextEditingController(text: '29');
  final TextEditingController narrationController = TextEditingController();
  final TextEditingController discountController = TextEditingController(text: '0');
  final TextEditingController referenceNumberController = TextEditingController();

  // Bill-To / Ship-To State
  bool _isBillToShipToDifferent = false;
  final TextEditingController shipToAddressController = TextEditingController();
  final TextEditingController shipToGstinController = TextEditingController(text: 'URP');

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

  // Drafting and Editing State
  String? _editingVoucherId;
  VoucherStatus _currentStatus = VoucherStatus.posted;
  String? _sourceVoucherId;
  VoucherModel? _loadedVoucher;

  VoucherFormController({
    required this.ref,
    Party? initialParty,
    VoucherType initialType = VoucherType.sales,
    VoucherModel? initialVoucher,
  }) : _selectedType = initialType,
       _selectedParty = initialParty {
    _selectedPaymentMode = initialParty != null ? PaymentMode.credit : PaymentMode.cash;

    if (initialVoucher != null) {
      loadVoucher(initialVoucher);
    } else {
      voucherNumberController.text =
          '${_selectedType.prefix}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      initializeDocumentNumber(_selectedType);

      if (_selectedParty != null) {
        if (_selectedParty!.gstin != null && _selectedParty!.gstin!.isNotEmpty) {
          partyGstinController.text = _selectedParty!.gstin!;
        }
        if (_selectedParty!.stateCode != null && _selectedParty!.stateCode!.isNotEmpty) {
          placeOfSupplyController.text = _selectedParty!.stateCode!;
        }
      }
    }
  }

  // Getters
  VoucherType get selectedType => _selectedType;
  DateTime get voucherDate => _voucherDate;
  DateTime? get dueDate => _dueDate;
  Party? get selectedParty => _selectedParty;
  PaymentMode get selectedPaymentMode => _selectedPaymentMode;
  bool get isBillToShipToDifferent => _isBillToShipToDifferent;
  bool get isValidatingGstin => _isValidatingGstin;
  GstValidationResult? get gstinValidationResult => _gstinValidationResult;
  List<VoucherItemModel> get items => List.unmodifiable(_items);
  EInvoiceDetails? get generatedEInvoice => _generatedEInvoice;
  EWayBillDetails? get generatedEWayBill => _generatedEWayBill;
  bool get isGeneratingEInvoice => _isGeneratingEInvoice;
  bool get isGeneratingEWayBill => _isGeneratingEWayBill;
  String? get complianceErrorMessage => _complianceErrorMessage;
  bool get isSaving => _isSaving;
  String? get editingVoucherId => _editingVoucherId;
  VoucherStatus get currentStatus => _currentStatus;
  String? get sourceVoucherId => _sourceVoucherId;
  VoucherModel? get loadedVoucher => _loadedVoucher;

  bool get isSalesOrder => _selectedType == VoucherType.salesOrder;
  bool get isEstimate => _selectedType == VoucherType.estimate;
  bool get isPurchase => _selectedType == VoucherType.purchase;
  bool get isSalesInvoice => _selectedType == VoucherType.sales;

  @override
  void dispose() {
    voucherNumberController.dispose();
    partyGstinController.dispose();
    placeOfSupplyController.dispose();
    narrationController.dispose();
    discountController.dispose();
    referenceNumberController.dispose();
    shipToAddressController.dispose();
    shipToGstinController.dispose();
    super.dispose();
  }

  Future<void> initializeDocumentNumber(VoucherType type) async {
    try {
      final repo = ref.read(voucherRepositoryProvider);
      final nextNumber = await repo.generateNextVoucherNumber(type);
      if (_editingVoucherId == null) {
        voucherNumberController.text = nextNumber;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to initialize document number for $type: $e');
    }
  }

  void onTypeChanged(VoucherType newType) {
    if (_selectedType == newType) return;
    HapticFeedback.selectionClick();

    _selectedType = newType;

    // Party validation adjustment
    if (_selectedParty != null) {
      final isSupplierParty = _selectedParty!.type == PartyType.supplier;
      final isPurchaseType = newType == VoucherType.purchase;
      if (isPurchaseType && !isSupplierParty) {
        _selectedParty = null;
        partyGstinController.clear();
      } else if (!isPurchaseType && isSupplierParty) {
        _selectedParty = null;
        partyGstinController.clear();
      }
    }

    // Default status adjustment
    if (_editingVoucherId == null) {
      switch (newType) {
        case VoucherType.sales:
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

    if (_editingVoucherId == null) {
      initializeDocumentNumber(newType);
    }
    notifyListeners();
  }

  void loadVoucher(VoucherModel v) {
    _loadedVoucher = v;
    _editingVoucherId = v.id;
    _selectedType = v.type;
    _currentStatus = v.status;
    _selectedPaymentMode = v.paymentMode;
    _voucherDate = v.date;
    _dueDate = v.dueDate;
    voucherNumberController.text = v.voucherNumber;
    placeOfSupplyController.text = v.placeOfSupplyStateCode ?? '29';
    narrationController.text = v.narration ?? '';
    referenceNumberController.text = v.referenceNumber ?? '';
    _sourceVoucherId = v.sourceVoucherId;
    discountController.text = (v.discountInCents / 100).toStringAsFixed(0);
    _items.clear();
    _items.addAll(v.items);
    _isBillToShipToDifferent = v.isBillToShipToDifferent;
    shipToAddressController.text = v.shipToAddress ?? '';
    shipToGstinController.text = v.shipToGstin ?? 'URP';
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
      _selectedParty = match;
      if (match.gstin != null && match.gstin!.isNotEmpty) {
        partyGstinController.text = match.gstin!;
      }
    }
    notifyListeners();
  }

  void startFresh() {
    _editingVoucherId = null;
    _loadedVoucher = null;
    _currentStatus = VoucherStatus.posted;
    _items.clear();
    initializeDocumentNumber(_selectedType);
    notifyListeners();
  }

  void setParty(Party? party) {
    _selectedParty = party;
    if (party != null) {
      if (party.gstin != null && party.gstin!.isNotEmpty) {
        partyGstinController.text = party.gstin!;
      }
      if (party.stateCode != null && party.stateCode!.isNotEmpty) {
        placeOfSupplyController.text = party.stateCode!;
      }
    }
    notifyListeners();
  }

  void setVoucherDate(DateTime date) {
    _voucherDate = date;
    notifyListeners();
  }

  void setDueDate(DateTime? date) {
    _dueDate = date;
    notifyListeners();
  }

  void setPaymentMode(PaymentMode mode) {
    _selectedPaymentMode = mode;
    notifyListeners();
  }

  void toggleBillToShipToDifferent(bool value) {
    _isBillToShipToDifferent = value;
    notifyListeners();
  }

  void addItem(VoucherItemModel item) {
    _items.add(item);
    notifyListeners();
  }

  void updateItem(int index, VoucherItemModel item) {
    if (index >= 0 && index < _items.length) {
      _items[index] = item;
      notifyListeners();
    }
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> validateGstin() async {
    final gstin = partyGstinController.text.trim();
    if (gstin.isEmpty) return;

    HapticFeedback.lightImpact();
    _isValidatingGstin = true;
    _gstinValidationResult = null;
    notifyListeners();

    final validator = ref.read(gstValidationServiceProvider);
    final result = await validator.searchGstin(gstin);

    _isValidatingGstin = false;
    _gstinValidationResult = result;
    if (result.isValid && result.details != null) {
      placeOfSupplyController.text = result.details!.stateCode;
    }
    notifyListeners();
  }

  GstTaxBreakdown calculateBreakdown(Company company) {
    final supplierState = company.stateCode ??
        (company.gstin != null && company.gstin!.length >= 2 ? company.gstin!.substring(0, 2) : '29');
    final supplierType = company.dealerType == 'composition'
        ? GstDealerType.composition
        : GstDealerType.regular;
    final pos = placeOfSupplyController.text.trim().isNotEmpty
        ? placeOfSupplyController.text.trim()
        : '29';
    final discountCents = ((double.tryParse(discountController.text) ?? 0.0) * 100).toInt();

    return GstTaxEngine.calculateTax(
      supplierStateCode: supplierState,
      supplierDealerType: supplierType,
      placeOfSupplyStateCode: pos,
      items: _items,
      discountInCents: discountCents,
    );
  }

  VoucherModel buildVoucherModel(
    Company company,
    Party party,
    GstTaxBreakdown breakdown, {
    VoucherStatus? status,
  }) {
    return VoucherModel(
      id: _editingVoucherId ?? 'vch_${DateTime.now().millisecondsSinceEpoch}',
      companyId: company.id,
      voucherNumber: voucherNumberController.text.trim().isNotEmpty
          ? voucherNumberController.text.trim()
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
      placeOfSupplyStateCode: placeOfSupplyController.text.trim(),
      irn: _generatedEInvoice?.irn,
      signedQrCode: _generatedEInvoice?.signedQrCode,
      eWayBillNumber: _generatedEWayBill?.eWayBillNumber,
      shipToAddress: _isBillToShipToDifferent ? shipToAddressController.text.trim() : null,
      shipToGstin: _isBillToShipToDifferent ? shipToGstinController.text.trim() : null,
      isBillToShipToDifferent: _isBillToShipToDifferent,
      narration: narrationController.text.trim(),
      referenceNumber: referenceNumberController.text.trim().isNotEmpty
          ? referenceNumberController.text.trim()
          : null,
      sourceVoucherId: _sourceVoucherId,
      createdAt: _loadedVoucher?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> generateEInvoice(Company company, Party party, BuildContext context) async {
    HapticFeedback.mediumImpact();
    _isGeneratingEInvoice = true;
    _complianceErrorMessage = null;
    notifyListeners();

    final service = ref.read(einvoiceEwaybillServiceProvider);
    final breakdown = calculateBreakdown(company);
    final voucher = buildVoucherModel(company, party, breakdown);

    final supplierGstin = company.gstin ?? '29ABCDE1234F1ZH';
    final buyerGstin = partyGstinController.text.trim().isNotEmpty
        ? partyGstinController.text.trim()
        : '29XYZDE9876K1Z2';

    final result = await service.generateEInvoice(
      voucher: voucher,
      supplierGstin: supplierGstin,
      buyerGstin: buyerGstin,
    );

    _isGeneratingEInvoice = false;
    if (result.success && result.details != null) {
      _generatedEInvoice = result.details;
      ref.read(subscriptionQuotaProvider.notifier).updateQuota(result.updatedQuota);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('e-Invoice IRN Generated: ${result.details!.irn.substring(0, 16)}...'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      }
    } else {
      _complianceErrorMessage = result.errorMessage;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Failed to generate e-Invoice'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> generateEWayBill(Company company, Party party, BuildContext context) async {
    HapticFeedback.mediumImpact();
    _isGeneratingEWayBill = true;
    _complianceErrorMessage = null;
    notifyListeners();

    final service = ref.read(einvoiceEwaybillServiceProvider);
    final breakdown = calculateBreakdown(company);
    final voucher = buildVoucherModel(company, party, breakdown);
    final supplierGstin = company.gstin ?? '29ABCDE1234F1ZH';

    final result = await service.generateEWayBill(
      voucher: voucher,
      supplierGstin: supplierGstin,
      isBillToShipToDifferent: _isBillToShipToDifferent,
      shipToGstinOrUrp: shipToGstinController.text.trim(),
      vehicleNumber: 'KA-01-MJ-5501',
      distanceKm: 180.0,
    );

    _isGeneratingEWayBill = false;
    if (result.success && result.details != null) {
      _generatedEWayBill = result.details;
      ref.read(subscriptionQuotaProvider.notifier).updateQuota(result.updatedQuota);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('e-Way Bill Generated: ${result.details!.eWayBillNumber}'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      }
    } else {
      _complianceErrorMessage = result.errorMessage;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Failed to generate e-Way Bill'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> saveVoucher(
    Company company,
    Party party,
    BuildContext context, {
    VoucherStatus status = VoucherStatus.posted,
  }) async {
    final requiresItems = (status == VoucherStatus.posted || status == VoucherStatus.confirmed);
    if (_items.isEmpty && requiresItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one line item before saving')),
      );
      return;
    }

    _isSaving = true;
    notifyListeners();
    HapticFeedback.mediumImpact();

    try {
      final breakdown = calculateBreakdown(company);
      final voucher = buildVoucherModel(company, party, breakdown, status: status);

      await ref.read(voucherControllerProvider.notifier).createVoucher(voucher);

      if (context.mounted) {
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
      if (context.mounted) {
        _isSaving = false;
        notifyListeners();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save document: $e'), backgroundColor: AppColors.payableRed),
        );
      }
    }
  }

  Future<void> previewAndExportPdf(Company company, Party party, BuildContext context) async {
    HapticFeedback.lightImpact();
    final breakdown = calculateBreakdown(company);
    final voucher = buildVoucherModel(company, party, breakdown);

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

    if (context.mounted) {
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

  Color getTypeAccentColor() {
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
}
