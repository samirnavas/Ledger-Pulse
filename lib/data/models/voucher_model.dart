import 'dart:convert';

enum VoucherType {
  sales,
  purchase,
  receipt,
  payment,
  contra,
  journal,
  expense,
  salesOrder,
  purchaseOrder,
  estimate,
  income,
  transfer;

  String get displayName {
    switch (this) {
      case VoucherType.sales:
        return 'Sales Invoice';
      case VoucherType.purchase:
        return 'Purchase Invoice';
      case VoucherType.receipt:
        return 'Payment Receipt (Got)';
      case VoucherType.payment:
        return 'Payment Voucher (Gave)';
      case VoucherType.contra:
        return 'Contra (Fund Transfer)';
      case VoucherType.journal:
        return 'Journal Entry';
      case VoucherType.expense:
        return 'Expense Voucher';
      case VoucherType.salesOrder:
        return 'Sales Order';
      case VoucherType.purchaseOrder:
        return 'Purchase Order';
      case VoucherType.estimate:
        return 'Estimate / Quotation';
      case VoucherType.income:
        return 'Income Voucher';
      case VoucherType.transfer:
        return 'Transfer Voucher';
    }
  }

  String get prefix {
    switch (this) {
      case VoucherType.sales:
        return 'INV';
      case VoucherType.purchase:
        return 'PUR';
      case VoucherType.salesOrder:
        return 'SO';
      case VoucherType.estimate:
        return 'EST';
      case VoucherType.purchaseOrder:
        return 'PO';
      case VoucherType.receipt:
        return 'REC';
      case VoucherType.payment:
        return 'PAY';
      case VoucherType.contra:
        return 'CON';
      case VoucherType.journal:
        return 'JNL';
      case VoucherType.expense:
        return 'EXP';
      case VoucherType.income:
        return 'INC';
      case VoucherType.transfer:
        return 'TRF';
    }
  }

  bool get isOrderOrEstimate =>
      this == VoucherType.salesOrder ||
      this == VoucherType.purchaseOrder ||
      this == VoucherType.estimate;

  bool get isFinancialPosting => !isOrderOrEstimate;

  bool get isSalesDocument =>
      this == VoucherType.sales ||
      this == VoucherType.salesOrder ||
      this == VoucherType.estimate;

  bool get isPurchaseDocument =>
      this == VoucherType.purchase ||
      this == VoucherType.purchaseOrder;
}

enum VoucherStatus {
  draft,
  onHold,
  posted,
  confirmed,
  sent,
  accepted,
  rejected,
  expired,
  converted,
  cancelled,
  voided;

  String get displayName {
    switch (this) {
      case VoucherStatus.draft:
        return 'Draft';
      case VoucherStatus.onHold:
        return 'On Hold';
      case VoucherStatus.posted:
        return 'Posted';
      case VoucherStatus.confirmed:
        return 'Confirmed';
      case VoucherStatus.sent:
        return 'Sent';
      case VoucherStatus.accepted:
        return 'Accepted';
      case VoucherStatus.rejected:
        return 'Rejected';
      case VoucherStatus.expired:
        return 'Expired';
      case VoucherStatus.converted:
        return 'Converted';
      case VoucherStatus.cancelled:
        return 'Cancelled';
      case VoucherStatus.voided:
        return 'Voided';
    }
  }

  bool get isDraft => this == VoucherStatus.draft;

  bool get isPosted =>
      this == VoucherStatus.posted || this == VoucherStatus.confirmed;

  bool get isClosedOrCancelled =>
      this == VoucherStatus.voided ||
      this == VoucherStatus.cancelled ||
      this == VoucherStatus.rejected ||
      this == VoucherStatus.expired;

  bool get canBeConverted =>
      (this == VoucherStatus.posted ||
          this == VoucherStatus.confirmed ||
          this == VoucherStatus.accepted ||
          this == VoucherStatus.draft ||
          this == VoucherStatus.sent) &&
      this != VoucherStatus.converted &&
      this != VoucherStatus.voided &&
      this != VoucherStatus.cancelled;
}

enum PaymentMode {
  cash,
  bank,
  credit,
  upi;

  String get displayName {
    switch (this) {
      case PaymentMode.cash:
        return 'Cash';
      case PaymentMode.bank:
        return 'Bank Transfer / Cheque';
      case PaymentMode.credit:
        return 'Credit (On Account)';
      case PaymentMode.upi:
        return 'UPI / Online';
    }
  }
}

class VoucherItemModel {
  final String itemId;
  final String itemName;
  final String sku;
  final String hsnCode;
  final double quantity;
  final String unit;
  final int unitPriceInCents;
  final double taxRatePercent;
  final int discountInCents;
  final int cgstInCents;
  final int sgstInCents;
  final int igstInCents;
  final int totalInCents;

  const VoucherItemModel({
    required this.itemId,
    required this.itemName,
    required this.sku,
    this.hsnCode = '',
    required this.quantity,
    this.unit = 'PCS',
    required this.unitPriceInCents,
    this.taxRatePercent = 0.0,
    this.discountInCents = 0,
    this.cgstInCents = 0,
    this.sgstInCents = 0,
    this.igstInCents = 0,
    required this.totalInCents,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'sku': sku,
      'hsnCode': hsnCode,
      'quantity': quantity,
      'unit': unit,
      'unitPriceInCents': unitPriceInCents,
      'taxRatePercent': taxRatePercent,
      'discountInCents': discountInCents,
      'cgstInCents': cgstInCents,
      'sgstInCents': sgstInCents,
      'igstInCents': igstInCents,
      'totalInCents': totalInCents,
    };
  }

  factory VoucherItemModel.fromMap(Map<String, dynamic> map) {
    return VoucherItemModel(
      itemId: map['itemId'] as String,
      itemName: map['itemName'] as String,
      sku: (map['sku'] as String?) ?? '',
      hsnCode: (map['hsnCode'] as String?) ?? '',
      quantity: (map['quantity'] as num).toDouble(),
      unit: (map['unit'] as String?) ?? 'PCS',
      unitPriceInCents: (map['unitPriceInCents'] as int?) ?? 0,
      taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 0.0,
      discountInCents: (map['discountInCents'] as int?) ?? 0,
      cgstInCents: (map['cgstInCents'] as int?) ?? 0,
      sgstInCents: (map['sgstInCents'] as int?) ?? 0,
      igstInCents: (map['igstInCents'] as int?) ?? 0,
      totalInCents: (map['totalInCents'] as int?) ?? 0,
    );
  }
}

class VoucherModel {
  final String id;
  final String companyId;
  final String voucherNumber;
  final VoucherType type;
  final DateTime date;
  final DateTime? dueDate;
  final String? partyId;
  final String? partyName;
  final VoucherStatus status;
  final PaymentMode paymentMode;
  final List<VoucherItemModel> items;
  final int subtotalInCents;
  final int taxInCents;
  final int cgstInCents;
  final int sgstInCents;
  final int igstInCents;
  final int discountInCents;
  final int totalAmountInCents;
  final String? placeOfSupplyStateCode;
  final String? irn;
  final String? signedQrCode;
  final String? eWayBillNumber;
  final String? shipToAddress;
  final String? shipToGstin;
  final bool isBillToShipToDifferent;
  final String? narration;
  final String? referenceNumber;
  final String? sourceVoucherId;
  final String? receiptPhotoUrl;
  final String? categoryAccountId;
  final String? walletAccountId;
  final String? toWalletAccountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VoucherModel({
    required this.id,
    required this.companyId,
    required this.voucherNumber,
    required this.type,
    required this.date,
    this.dueDate,
    this.partyId,
    this.partyName,
    this.status = VoucherStatus.posted,
    this.paymentMode = PaymentMode.credit,
    this.items = const [],
    this.subtotalInCents = 0,
    this.taxInCents = 0,
    this.cgstInCents = 0,
    this.sgstInCents = 0,
    this.igstInCents = 0,
    this.discountInCents = 0,
    required this.totalAmountInCents,
    this.placeOfSupplyStateCode,
    this.irn,
    this.signedQrCode,
    this.eWayBillNumber,
    this.shipToAddress,
    this.shipToGstin,
    this.isBillToShipToDifferent = false,
    this.narration,
    this.referenceNumber,
    this.sourceVoucherId,
    this.receiptPhotoUrl,
    this.categoryAccountId,
    this.walletAccountId,
    this.toWalletAccountId,
    required this.createdAt,
    required this.updatedAt,
  });

  VoucherModel copyWith({
    String? id,
    String? companyId,
    String? voucherNumber,
    VoucherType? type,
    DateTime? date,
    DateTime? dueDate,
    String? partyId,
    String? partyName,
    VoucherStatus? status,
    PaymentMode? paymentMode,
    List<VoucherItemModel>? items,
    int? subtotalInCents,
    int? taxInCents,
    int? cgstInCents,
    int? sgstInCents,
    int? igstInCents,
    int? discountInCents,
    int? totalAmountInCents,
    String? placeOfSupplyStateCode,
    String? irn,
    String? signedQrCode,
    String? eWayBillNumber,
    String? shipToAddress,
    String? shipToGstin,
    bool? isBillToShipToDifferent,
    String? narration,
    String? referenceNumber,
    String? sourceVoucherId,
    String? receiptPhotoUrl,
    String? categoryAccountId,
    String? walletAccountId,
    String? toWalletAccountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VoucherModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      type: type ?? this.type,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      partyId: partyId ?? this.partyId,
      partyName: partyName ?? this.partyName,
      status: status ?? this.status,
      paymentMode: paymentMode ?? this.paymentMode,
      items: items ?? this.items,
      subtotalInCents: subtotalInCents ?? this.subtotalInCents,
      taxInCents: taxInCents ?? this.taxInCents,
      cgstInCents: cgstInCents ?? this.cgstInCents,
      sgstInCents: sgstInCents ?? this.sgstInCents,
      igstInCents: igstInCents ?? this.igstInCents,
      discountInCents: discountInCents ?? this.discountInCents,
      totalAmountInCents: totalAmountInCents ?? this.totalAmountInCents,
      placeOfSupplyStateCode: placeOfSupplyStateCode ?? this.placeOfSupplyStateCode,
      irn: irn ?? this.irn,
      signedQrCode: signedQrCode ?? this.signedQrCode,
      eWayBillNumber: eWayBillNumber ?? this.eWayBillNumber,
      shipToAddress: shipToAddress ?? this.shipToAddress,
      shipToGstin: shipToGstin ?? this.shipToGstin,
      isBillToShipToDifferent: isBillToShipToDifferent ?? this.isBillToShipToDifferent,
      narration: narration ?? this.narration,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      sourceVoucherId: sourceVoucherId ?? this.sourceVoucherId,
      receiptPhotoUrl: receiptPhotoUrl ?? this.receiptPhotoUrl,
      categoryAccountId: categoryAccountId ?? this.categoryAccountId,
      walletAccountId: walletAccountId ?? this.walletAccountId,
      toWalletAccountId: toWalletAccountId ?? this.toWalletAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'voucherNumber': voucherNumber,
      'type': type.name,
      'date': date.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'partyId': partyId,
      'partyName': partyName,
      'status': status.name,
      'paymentMode': paymentMode.name,
      'items': items.map((i) => i.toMap()).toList(),
      'subtotalInCents': subtotalInCents,
      'taxInCents': taxInCents,
      'cgstInCents': cgstInCents,
      'sgstInCents': sgstInCents,
      'igstInCents': igstInCents,
      'discountInCents': discountInCents,
      'totalAmountInCents': totalAmountInCents,
      'placeOfSupplyStateCode': placeOfSupplyStateCode,
      'irn': irn,
      'signedQrCode': signedQrCode,
      'eWayBillNumber': eWayBillNumber,
      'shipToAddress': shipToAddress,
      'shipToGstin': shipToGstin,
      'isBillToShipToDifferent': isBillToShipToDifferent ? 1 : 0,
      'narration': narration,
      'referenceNumber': referenceNumber,
      'sourceVoucherId': sourceVoucherId,
      'receiptPhotoUrl': receiptPhotoUrl,
      'categoryAccountId': categoryAccountId,
      'walletAccountId': walletAccountId,
      'toWalletAccountId': toWalletAccountId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory VoucherModel.fromMap(Map<String, dynamic> map) {
    List<VoucherItemModel> parsedItems = [];
    if (map['items'] is List) {
      parsedItems = (map['items'] as List<dynamic>)
          .map((i) => VoucherItemModel.fromMap(i as Map<String, dynamic>))
          .toList();
    } else if (map['itemsJson'] is String && (map['itemsJson'] as String).isNotEmpty) {
      final decoded = jsonDecode(map['itemsJson'] as String);
      if (decoded is List) {
        parsedItems = decoded
            .map((i) => VoucherItemModel.fromMap(i as Map<String, dynamic>))
            .toList();
      }
    }

    return VoucherModel(
      id: map['id'] as String,
      companyId: (map['companyId'] as String?) ?? 'cmp_default',
      voucherNumber: (map['voucherNumber'] as String?) ?? 'VCH-001',
      type: VoucherType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => VoucherType.sales,
      ),
      date: DateTime.parse(map['date'] as String),
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate'] as String) : null,
      partyId: map['partyId'] as String?,
      partyName: map['partyName'] as String?,
      status: map['status'] != null
          ? VoucherStatus.values.firstWhere(
              (e) => e.name == map['status'],
              orElse: () => VoucherStatus.posted,
            )
          : VoucherStatus.posted,
      paymentMode: map['paymentMode'] != null
          ? PaymentMode.values.firstWhere(
              (e) => e.name == map['paymentMode'],
              orElse: () => PaymentMode.cash,
            )
          : PaymentMode.cash,
      items: parsedItems,
      subtotalInCents: (map['subtotalInCents'] as int?) ?? 0,
      taxInCents: (map['taxInCents'] as int?) ?? 0,
      cgstInCents: (map['cgstInCents'] as int?) ?? 0,
      sgstInCents: (map['sgstInCents'] as int?) ?? 0,
      igstInCents: (map['igstInCents'] as int?) ?? 0,
      discountInCents: (map['discountInCents'] as int?) ?? 0,
      totalAmountInCents: (map['totalAmountInCents'] as int?) ?? 0,
      placeOfSupplyStateCode: map['placeOfSupplyStateCode'] as String?,
      irn: map['irn'] as String?,
      signedQrCode: map['signedQrCode'] as String?,
      eWayBillNumber: map['eWayBillNumber'] as String?,
      shipToAddress: map['shipToAddress'] as String?,
      shipToGstin: map['shipToGstin'] as String?,
      isBillToShipToDifferent: map['isBillToShipToDifferent'] == 1 ||
          map['isBillToShipToDifferent'] == true,
      narration: map['narration'] as String?,
      referenceNumber: map['referenceNumber'] as String?,
      sourceVoucherId: map['sourceVoucherId'] as String?,
      receiptPhotoUrl: map['receiptPhotoUrl'] as String?,
      categoryAccountId: (map['categoryAccountId'] ?? map['category_account_id']) as String?,
      walletAccountId: (map['walletAccountId'] ?? map['wallet_account_id']) as String?,
      toWalletAccountId: (map['toWalletAccountId'] ?? map['to_wallet_account_id']) as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}
