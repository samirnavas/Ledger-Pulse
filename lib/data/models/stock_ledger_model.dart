enum StockTransactionType {
  inward,
  outward,
  adjustment,
  wastage;

  String get displayName {
    switch (this) {
      case StockTransactionType.inward:
        return 'Inward (Purchase/Return)';
      case StockTransactionType.outward:
        return 'Outward (Sale/Issue)';
      case StockTransactionType.adjustment:
        return 'Stock Adjustment';
      case StockTransactionType.wastage:
        return 'Wastage / Damage';
    }
  }
}

class StockLedgerEntry {
  final String id;
  final String companyId;
  final String itemId;
  final String? voucherId;
  final StockTransactionType transactionType;
  final double quantity;
  final int unitCostInCents;
  final int totalCostInCents;
  final double runningStockQuantity;
  final DateTime date;
  final String? note;
  final DateTime createdAt;

  const StockLedgerEntry({
    required this.id,
    required this.companyId,
    required this.itemId,
    this.voucherId,
    required this.transactionType,
    required this.quantity,
    required this.unitCostInCents,
    required this.totalCostInCents,
    required this.runningStockQuantity,
    required this.date,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'itemId': itemId,
      'voucherId': voucherId,
      'transactionType': transactionType.name,
      'quantity': quantity,
      'unitCostInCents': unitCostInCents,
      'totalCostInCents': totalCostInCents,
      'runningStockQuantity': runningStockQuantity,
      'date': date.toIso8601String(),
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StockLedgerEntry.fromMap(Map<String, dynamic> map) {
    return StockLedgerEntry(
      id: map['id'] as String,
      companyId: (map['companyId'] as String?) ?? 'cmp_default',
      itemId: map['itemId'] as String,
      voucherId: map['voucherId'] as String?,
      transactionType: StockTransactionType.values.byName(map['transactionType'] as String),
      quantity: (map['quantity'] as num).toDouble(),
      unitCostInCents: (map['unitCostInCents'] as int?) ?? 0,
      totalCostInCents: (map['totalCostInCents'] as int?) ?? 0,
      runningStockQuantity: (map['runningStockQuantity'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
