/// Taxpayer registration type under Indian GST
enum GstDealerType {
  regular,
  composition,
  unregistered,
  consumer;

  String get displayName {
    switch (this) {
      case GstDealerType.regular:
        return 'Regular Dealer';
      case GstDealerType.composition:
        return 'Composition Dealer';
      case GstDealerType.unregistered:
        return 'Unregistered Business';
      case GstDealerType.consumer:
        return 'Consumer (B2C)';
    }
  }

  bool get isComposition => this == GstDealerType.composition;
  bool get isRegular => this == GstDealerType.regular;
}

/// Dynamic invoice templates supported by Ludgerpulse
enum InvoiceTemplateType {
  modernExpressive,
  classicCorporate,
  gstStatutory,
  compactPos;

  String get displayName {
    switch (this) {
      case InvoiceTemplateType.modernExpressive:
        return 'Modern Expressive';
      case InvoiceTemplateType.classicCorporate:
        return 'Classic Corporate';
      case InvoiceTemplateType.gstStatutory:
        return 'GST Tax Invoice (Statutory)';
      case InvoiceTemplateType.compactPos:
        return 'Compact POS Slip';
    }
  }

  String get description {
    switch (this) {
      case InvoiceTemplateType.modernExpressive:
        return 'Contemporary design with colored badge headers and clean cards';
      case InvoiceTemplateType.classicCorporate:
        return 'Traditional bordered accounting format with two-column header';
      case InvoiceTemplateType.gstStatutory:
        return 'Complete Indian GST format with HSN summary, IRN, and QR code';
      case InvoiceTemplateType.compactPos:
        return 'Condensed thermal receipt format optimized for quick billing';
    }
  }
}

/// Representation of verified GSTIN details
class GstinDetails {
  final String gstin;
  final String legalName;
  final String tradeName;
  final String stateCode;
  final String stateName;
  final GstDealerType dealerType;
  final String address;
  final bool isActive;
  final DateTime? registrationDate;

  const GstinDetails({
    required this.gstin,
    required this.legalName,
    required this.tradeName,
    required this.stateCode,
    required this.stateName,
    required this.dealerType,
    required this.address,
    this.isActive = true,
    this.registrationDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'gstin': gstin,
      'legalName': legalName,
      'tradeName': tradeName,
      'stateCode': stateCode,
      'stateName': stateName,
      'dealerType': dealerType.name,
      'address': address,
      'isActive': isActive,
      'registrationDate': registrationDate?.toIso8601String(),
    };
  }

  factory GstinDetails.fromMap(Map<String, dynamic> map) {
    return GstinDetails(
      gstin: map['gstin'] as String,
      legalName: (map['legalName'] as String?) ?? '',
      tradeName: (map['tradeName'] as String?) ?? map['legalName'] ?? '',
      stateCode: (map['stateCode'] as String?) ?? '',
      stateName: (map['stateName'] as String?) ?? '',
      dealerType: map['dealerType'] != null
          ? GstDealerType.values.byName(map['dealerType'] as String)
          : GstDealerType.regular,
      address: (map['address'] as String?) ?? '',
      isActive: (map['isActive'] as bool?) ?? true,
      registrationDate: map['registrationDate'] != null
          ? DateTime.parse(map['registrationDate'] as String)
          : null,
    );
  }
}

/// Tax calculation breakdown for an invoice or voucher
class GstTaxBreakdown {
  final int subtotalInCents;
  final int cgstInCents;
  final int sgstInCents;
  final int igstInCents;
  final int totalTaxInCents;
  final int discountInCents;
  final int roundOffInCents;
  final int totalAmountInCents;
  final bool isIntraState;
  final bool isComposition;
  final List<GstItemTaxLine> itemLines;

  const GstTaxBreakdown({
    required this.subtotalInCents,
    this.cgstInCents = 0,
    this.sgstInCents = 0,
    this.igstInCents = 0,
    required this.totalTaxInCents,
    this.discountInCents = 0,
    this.roundOffInCents = 0,
    required this.totalAmountInCents,
    required this.isIntraState,
    required this.isComposition,
    this.itemLines = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'subtotalInCents': subtotalInCents,
      'cgstInCents': cgstInCents,
      'sgstInCents': sgstInCents,
      'igstInCents': igstInCents,
      'totalTaxInCents': totalTaxInCents,
      'discountInCents': discountInCents,
      'roundOffInCents': roundOffInCents,
      'totalAmountInCents': totalAmountInCents,
      'isIntraState': isIntraState,
      'isComposition': isComposition,
      'itemLines': itemLines.map((e) => e.toMap()).toList(),
    };
  }
}

/// Item-level tax calculation breakdown
class GstItemTaxLine {
  final String itemId;
  final String itemName;
  final String hsnCode;
  final double quantity;
  final int unitPriceInCents;
  final int taxableAmountInCents;
  final double taxRatePercent;
  final int cgstInCents;
  final int sgstInCents;
  final int igstInCents;
  final int totalItemTaxInCents;
  final int finalItemTotalInCents;

  const GstItemTaxLine({
    required this.itemId,
    required this.itemName,
    required this.hsnCode,
    required this.quantity,
    required this.unitPriceInCents,
    required this.taxableAmountInCents,
    required this.taxRatePercent,
    this.cgstInCents = 0,
    this.sgstInCents = 0,
    this.igstInCents = 0,
    required this.totalItemTaxInCents,
    required this.finalItemTotalInCents,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'hsnCode': hsnCode,
      'quantity': quantity,
      'unitPriceInCents': unitPriceInCents,
      'taxableAmountInCents': taxableAmountInCents,
      'taxRatePercent': taxRatePercent,
      'cgstInCents': cgstInCents,
      'sgstInCents': sgstInCents,
      'igstInCents': igstInCents,
      'totalItemTaxInCents': totalItemTaxInCents,
      'finalItemTotalInCents': finalItemTotalInCents,
    };
  }
}

/// Statutory e-Invoice (IRN) details
class EInvoiceDetails {
  final String irn;
  final String ackNumber;
  final DateTime ackDate;
  final String signedQrCode;
  final String signedInvoice;
  final String status;

  const EInvoiceDetails({
    required this.irn,
    required this.ackNumber,
    required this.ackDate,
    required this.signedQrCode,
    this.signedInvoice = '',
    this.status = 'ACT',
  });

  Map<String, dynamic> toMap() {
    return {
      'irn': irn,
      'ackNumber': ackNumber,
      'ackDate': ackDate.toIso8601String(),
      'signedQrCode': signedQrCode,
      'signedInvoice': signedInvoice,
      'status': status,
    };
  }

  factory EInvoiceDetails.fromMap(Map<String, dynamic> map) {
    return EInvoiceDetails(
      irn: map['irn'] as String,
      ackNumber: map['ackNumber'] as String,
      ackDate: DateTime.parse(map['ackDate'] as String),
      signedQrCode: map['signedQrCode'] as String,
      signedInvoice: (map['signedInvoice'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'ACT',
    );
  }
}

/// Statutory e-Way Bill details
class EWayBillDetails {
  final String eWayBillNumber;
  final DateTime generatedDate;
  final DateTime validUptoDate;
  final String? transporterId;
  final String? transporterName;
  final String? vehicleNumber;
  final double distanceKm;
  final String shipToGstinOrUrp;
  final bool isBillToShipToDifferent;
  final String status;

  const EWayBillDetails({
    required this.eWayBillNumber,
    required this.generatedDate,
    required this.validUptoDate,
    this.transporterId,
    this.transporterName,
    this.vehicleNumber,
    this.distanceKm = 100.0,
    required this.shipToGstinOrUrp,
    this.isBillToShipToDifferent = false,
    this.status = 'ACTIVE',
  });

  Map<String, dynamic> toMap() {
    return {
      'eWayBillNumber': eWayBillNumber,
      'generatedDate': generatedDate.toIso8601String(),
      'validUptoDate': validUptoDate.toIso8601String(),
      'transporterId': transporterId,
      'transporterName': transporterName,
      'vehicleNumber': vehicleNumber,
      'distanceKm': distanceKm,
      'shipToGstinOrUrp': shipToGstinOrUrp,
      'isBillToShipToDifferent': isBillToShipToDifferent,
      'status': status,
    };
  }

  factory EWayBillDetails.fromMap(Map<String, dynamic> map) {
    return EWayBillDetails(
      eWayBillNumber: map['eWayBillNumber'] as String,
      generatedDate: DateTime.parse(map['generatedDate'] as String),
      validUptoDate: DateTime.parse(map['validUptoDate'] as String),
      transporterId: map['transporterId'] as String?,
      transporterName: map['transporterName'] as String?,
      vehicleNumber: map['vehicleNumber'] as String?,
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 100.0,
      shipToGstinOrUrp: (map['shipToGstinOrUrp'] as String?) ?? 'URP',
      isBillToShipToDifferent: (map['isBillToShipToDifferent'] as bool?) ?? false,
      status: (map['status'] as String?) ?? 'ACTIVE',
    );
  }
}

/// Subscription Quotas for government portal integrations
class SubscriptionQuota {
  final String tierName; // Free, Growth, Enterprise
  final int eInvoicesUsedThisMonth;
  final int eInvoicesMonthlyQuota;
  final int eWayBillsUsedThisMonth;
  final int eWayBillsMonthlyQuota;

  const SubscriptionQuota({
    this.tierName = 'Enterprise',
    this.eInvoicesUsedThisMonth = 12,
    this.eInvoicesMonthlyQuota = 500,
    this.eWayBillsUsedThisMonth = 8,
    this.eWayBillsMonthlyQuota = 500,
  });

  bool get hasRemainingEInvoiceQuota =>
      eInvoicesMonthlyQuota < 0 || eInvoicesUsedThisMonth < eInvoicesMonthlyQuota;

  bool get hasRemainingEWayBillQuota =>
      eWayBillsMonthlyQuota < 0 || eWayBillsUsedThisMonth < eWayBillsMonthlyQuota;

  SubscriptionQuota copyWith({
    String? tierName,
    int? eInvoicesUsedThisMonth,
    int? eInvoicesMonthlyQuota,
    int? eWayBillsUsedThisMonth,
    int? eWayBillsMonthlyQuota,
  }) {
    return SubscriptionQuota(
      tierName: tierName ?? this.tierName,
      eInvoicesUsedThisMonth: eInvoicesUsedThisMonth ?? this.eInvoicesUsedThisMonth,
      eInvoicesMonthlyQuota: eInvoicesMonthlyQuota ?? this.eInvoicesMonthlyQuota,
      eWayBillsUsedThisMonth: eWayBillsUsedThisMonth ?? this.eWayBillsUsedThisMonth,
      eWayBillsMonthlyQuota: eWayBillsMonthlyQuota ?? this.eWayBillsMonthlyQuota,
    );
  }
}

/// User customization options for invoice branding
class InvoiceCustomization {
  final String? logoPath;
  final List<int>? logoBytes;
  final String? signaturePath;
  final List<int>? signatureBytes;
  final String authorizedSignatoryName;
  final String authorizedSignatoryDesignation;
  final String bankName;
  final String bankAccountNumber;
  final String bankIfsc;
  final String upiId;
  final String termsAndConditions;

  const InvoiceCustomization({
    this.logoPath,
    this.logoBytes,
    this.signaturePath,
    this.signatureBytes,
    this.authorizedSignatoryName = 'Authorized Signatory',
    this.authorizedSignatoryDesignation = 'Finance Director',
    this.bankName = 'HDFC Bank Ltd',
    this.bankAccountNumber = '50200012345678',
    this.bankIfsc = 'HDFC0001234',
    this.upiId = 'ledgerpulse@hdfcbank',
    this.termsAndConditions =
        '1. Payment is due within 15 days of invoice date.\n2. Goods once sold will not be returned.',
  });

  InvoiceCustomization copyWith({
    String? logoPath,
    List<int>? logoBytes,
    String? signaturePath,
    List<int>? signatureBytes,
    String? authorizedSignatoryName,
    String? authorizedSignatoryDesignation,
    String? bankName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? upiId,
    String? termsAndConditions,
  }) {
    return InvoiceCustomization(
      logoPath: logoPath ?? this.logoPath,
      logoBytes: logoBytes ?? this.logoBytes,
      signaturePath: signaturePath ?? this.signaturePath,
      signatureBytes: signatureBytes ?? this.signatureBytes,
      authorizedSignatoryName:
          authorizedSignatoryName ?? this.authorizedSignatoryName,
      authorizedSignatoryDesignation:
          authorizedSignatoryDesignation ?? this.authorizedSignatoryDesignation,
      bankName: bankName ?? this.bankName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      upiId: upiId ?? this.upiId,
      termsAndConditions: termsAndConditions ?? this.termsAndConditions,
    );
  }
}
