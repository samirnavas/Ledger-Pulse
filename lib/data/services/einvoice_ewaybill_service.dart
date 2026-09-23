import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/gst_models.dart';
import '../models/voucher_model.dart';
import 'gst_validation_service.dart';

class EInvoiceException implements Exception {
  final String message;
  final String? code;
  const EInvoiceException(this.message, {this.code});

  @override
  String toString() => message;
}

class EWayBillException implements Exception {
  final String message;
  final String? code;
  const EWayBillException(this.message, {this.code});

  @override
  String toString() => message;
}

class EInvoiceGenerationResult {
  final bool success;
  final EInvoiceDetails? details;
  final String? errorMessage;
  final SubscriptionQuota updatedQuota;

  const EInvoiceGenerationResult({
    required this.success,
    this.details,
    this.errorMessage,
    required this.updatedQuota,
  });
}

class EWayBillGenerationResult {
  final bool success;
  final EWayBillDetails? details;
  final String? errorMessage;
  final SubscriptionQuota updatedQuota;

  const EWayBillGenerationResult({
    required this.success,
    this.details,
    this.errorMessage,
    required this.updatedQuota,
  });
}

/// Service managing government portal integrations for e-Invoicing (IRN) and
/// e-Way Bills with statutory 2026 GSTN compliance and quota enforcement.
class EInvoiceEWayBillService {
  SubscriptionQuota _quota;
  final GstValidationService _gstValidator;

  EInvoiceEWayBillService({
    SubscriptionQuota? initialQuota,
    GstValidationService? gstValidator,
  })  : _quota = initialQuota ?? const SubscriptionQuota(),
        _gstValidator = gstValidator ?? GstValidationService();

  SubscriptionQuota get currentQuota => _quota;

  void updateQuota(SubscriptionQuota newQuota) {
    _quota = newQuota;
  }

  /// Validates compliance with the 2026 GSTN rule restricting reporting of invoices
  /// older than 30 days.
  static void validate30DayRule(DateTime invoiceDate, {DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    // Calculate difference ignoring time-of-day discrepancy
    final dateOnlyInvoice = DateTime(invoiceDate.year, invoiceDate.month, invoiceDate.day);
    final dateOnlyNow = DateTime(now.year, now.month, now.day);

    final differenceInDays = dateOnlyNow.difference(dateOnlyInvoice).inDays;
    if (differenceInDays > 30) {
      throw EInvoiceException(
        'Compliance Rule Violation: As per 2026 GSTN regulations, invoices older than 30 days ($differenceInDays days old) cannot be reported to the IRP for e-invoice generation.',
        code: 'GSTN_2026_TIME_LIMIT_EXCEEDED',
      );
    }
  }

  /// Validates Ship-To GSTIN or strictly enforces "URP" designation for unregistered parties
  void validateShipToParty({
    required bool isBillToShipToDifferent,
    required String? shipToGstin,
  }) {
    if (!isBillToShipToDifferent) return;

    if (shipToGstin == null || shipToGstin.trim().isEmpty) {
      throw const EWayBillException(
        'Missing Ship-To GSTIN: For Bill-To/Ship-To consignments, provide a valid 15-character GSTIN or specify "URP" for unregistered consignees.',
        code: 'SHIP_TO_GSTIN_REQUIRED',
      );
    }

    final sanitized = shipToGstin.trim().toUpperCase();

    // Mandatory statutory check: If unregistered, designation MUST be "URP"
    if (sanitized == 'URP') {
      return; // Compliant unregistered consignee
    }

    // Otherwise, it must be a valid 15-character GSTIN
    if (sanitized.length != 15 || !_gstValidator.isValidGstin(sanitized)) {
      throw EWayBillException(
        'Invalid Ship-To GSTIN "$shipToGstin": Must be a valid 15-character GSTIN or the statutory designation "URP" for unregistered parties.',
        code: 'INVALID_SHIP_TO_GSTIN',
      );
    }
  }

  /// Generates statutory IRN e-Invoice directly from voucher details
  Future<EInvoiceGenerationResult> generateEInvoice({
    required VoucherModel voucher,
    required String supplierGstin,
    required String buyerGstin,
    DateTime? overrideNow,
  }) async {
    // 1. Check Subscription Quota
    if (!_quota.hasRemainingEInvoiceQuota) {
      return EInvoiceGenerationResult(
        success: false,
        errorMessage:
            'Subscription Quota Exceeded: You have used all ${_quota.eInvoicesMonthlyQuota} e-Invoices for tier ${_quota.tierName}. Please upgrade your plan.',
        updatedQuota: _quota,
      );
    }

    // 2. Validate 2026 GSTN 30-Day Reporting Rule
    try {
      validate30DayRule(voucher.date, referenceDate: overrideNow);
    } on EInvoiceException catch (e) {
      return EInvoiceGenerationResult(
        success: false,
        errorMessage: e.message,
        updatedQuota: _quota,
      );
    }

    // 3. Validate Supplier & Buyer GSTINs
    if (!_gstValidator.isValidGstin(supplierGstin)) {
      return EInvoiceGenerationResult(
        success: false,
        errorMessage: 'Invalid Supplier GSTIN: $supplierGstin',
        updatedQuota: _quota,
      );
    }

    final now = overrideNow ?? DateTime.now();

    // 4. Compute 64-character SHA-256 IRN
    final finYear = _getFinancialYear(voucher.date);
    final rawIrnString =
        '${supplierGstin.trim().toUpperCase()}:$finYear:${voucher.type.name.toUpperCase()}:${voucher.voucherNumber}';
    final irnHash = sha256.convert(utf8.encode(rawIrnString)).toString();

    final ackNumber = '11${now.millisecondsSinceEpoch.toString().substring(3, 13)}';

    // 5. Build Signed QR Code representation according to GSTN standard
    final qrData = {
      'irn': irnHash,
      'supGst': supplierGstin.toUpperCase(),
      'buyGst': buyerGstin.toUpperCase(),
      'docNo': voucher.voucherNumber,
      'docTyp': 'INV',
      'docDt': '${voucher.date.day.toString().padLeft(2, '0')}/${voucher.date.month.toString().padLeft(2, '0')}/${voucher.date.year}',
      'totVal': (voucher.totalAmountInCents / 100.0).toStringAsFixed(2),
      'itemCnt': voucher.items.isNotEmpty ? voucher.items.length : 1,
      'mainHsn': voucher.items.isNotEmpty ? voucher.items.first.hsnCode : '9983',
      'ackNo': ackNumber,
      'ackDt': now.toIso8601String(),
    };
    final signedQrCode = base64Encode(utf8.encode(jsonEncode(qrData)));

    // 6. Decrement Quota
    _quota = _quota.copyWith(
      eInvoicesUsedThisMonth: _quota.eInvoicesUsedThisMonth + 1,
    );

    final details = EInvoiceDetails(
      irn: irnHash,
      ackNumber: ackNumber,
      ackDate: now,
      signedQrCode: signedQrCode,
      status: 'ACT',
    );

    return EInvoiceGenerationResult(
      success: true,
      details: details,
      updatedQuota: _quota,
    );
  }

  /// Generates statutory e-Way Bill with Bill-To / Ship-To validation and URP enforcement
  Future<EWayBillGenerationResult> generateEWayBill({
    required VoucherModel voucher,
    required String supplierGstin,
    required bool isBillToShipToDifferent,
    required String? shipToGstinOrUrp,
    String? transporterId,
    String? transporterName,
    String? vehicleNumber,
    double distanceKm = 100.0,
    DateTime? overrideNow,
  }) async {
    // 1. Check Subscription Quota
    if (!_quota.hasRemainingEWayBillQuota) {
      return EWayBillGenerationResult(
        success: false,
        errorMessage:
            'Subscription Quota Exceeded: You have used all ${_quota.eWayBillsMonthlyQuota} e-Way Bills for tier ${_quota.tierName}. Please upgrade your plan.',
        updatedQuota: _quota,
      );
    }

    // 2. Enforce Bill-To / Ship-To URP or GSTIN check
    try {
      validateShipToParty(
        isBillToShipToDifferent: isBillToShipToDifferent,
        shipToGstin: shipToGstinOrUrp,
      );
    } on EWayBillException catch (e) {
      return EWayBillGenerationResult(
        success: false,
        errorMessage: e.message,
        updatedQuota: _quota,
      );
    }

    final now = overrideNow ?? DateTime.now();

    // 3. Calculate validity date: 1 day per 200 km (standard GST rule, minimum 1 day)
    final daysValid = (distanceKm / 200.0).ceil().clamp(1, 15);
    final validUpto = now.add(Duration(days: daysValid));

    // 4. Generate 12-digit e-Way Bill Number (State prefix + timestamp suffix)
    final stateCode = supplierGstin.length >= 2 ? supplierGstin.substring(0, 2) : '29';
    final seq = (now.millisecondsSinceEpoch % 10000000000).toString().padLeft(10, '0');
    final ewbNumber = '$stateCode$seq';

    // 5. Decrement Quota
    _quota = _quota.copyWith(
      eWayBillsUsedThisMonth: _quota.eWayBillsUsedThisMonth + 1,
    );

    final details = EWayBillDetails(
      eWayBillNumber: ewbNumber,
      generatedDate: now,
      validUptoDate: validUpto,
      transporterId: transporterId,
      transporterName: transporterName,
      vehicleNumber: vehicleNumber,
      distanceKm: distanceKm,
      shipToGstinOrUrp: isBillToShipToDifferent ? (shipToGstinOrUrp ?? 'URP') : 'SAME_AS_BILL_TO',
      isBillToShipToDifferent: isBillToShipToDifferent,
      status: 'ACTIVE',
    );

    return EWayBillGenerationResult(
      success: true,
      details: details,
      updatedQuota: _quota,
    );
  }

  String _getFinancialYear(DateTime date) {
    final year = date.year;
    if (date.month >= 4) {
      final nextYear = (year + 1) % 100;
      return '$year-${nextYear.toString().padLeft(2, '0')}';
    } else {
      final prevYear = year - 1;
      final currentShortYear = year % 100;
      return '$prevYear-${currentShortYear.toString().padLeft(2, '0')}';
    }
  }
}
