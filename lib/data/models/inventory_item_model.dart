class InventoryItem {
  final String id;
  final String companyId;
  final String sku;
  final String name;
  final String? description;
  final String unit; // PCS, KG, BOX, MTR, LTR, etc.
  final int purchasePriceInCents;
  final int sellingPriceInCents;
  final double currentStockQuantity;
  final double minimumStockAlert;
  final String? hsnCode;
  final double taxRatePercent;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryItem({
    required this.id,
    required this.companyId,
    required this.sku,
    required this.name,
    this.description,
    this.unit = 'PCS',
    this.purchasePriceInCents = 0,
    this.sellingPriceInCents = 0,
    this.currentStockQuantity = 0.0,
    this.minimumStockAlert = 5.0,
    this.hsnCode,
    this.taxRatePercent = 0.0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLowStock => currentStockQuantity <= minimumStockAlert;

  InventoryItem copyWith({
    String? id,
    String? companyId,
    String? sku,
    String? name,
    String? description,
    String? unit,
    int? purchasePriceInCents,
    int? sellingPriceInCents,
    double? currentStockQuantity,
    double? minimumStockAlert,
    String? hsnCode,
    double? taxRatePercent,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      purchasePriceInCents: purchasePriceInCents ?? this.purchasePriceInCents,
      sellingPriceInCents: sellingPriceInCents ?? this.sellingPriceInCents,
      currentStockQuantity: currentStockQuantity ?? this.currentStockQuantity,
      minimumStockAlert: minimumStockAlert ?? this.minimumStockAlert,
      hsnCode: hsnCode ?? this.hsnCode,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'sku': sku,
      'name': name,
      'description': description,
      'unit': unit,
      'purchasePriceInCents': purchasePriceInCents,
      'sellingPriceInCents': sellingPriceInCents,
      'currentStockQuantity': currentStockQuantity,
      'minimumStockAlert': minimumStockAlert,
      'hsnCode': hsnCode,
      'taxRatePercent': taxRatePercent,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String,
      companyId: (map['companyId'] as String?) ?? 'cmp_default',
      sku: map['sku'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      unit: (map['unit'] as String?) ?? 'PCS',
      purchasePriceInCents: (map['purchasePriceInCents'] as int?) ?? 0,
      sellingPriceInCents: (map['sellingPriceInCents'] as int?) ?? 0,
      currentStockQuantity: (map['currentStockQuantity'] as num?)?.toDouble() ?? 0.0,
      minimumStockAlert: (map['minimumStockAlert'] as num?)?.toDouble() ?? 5.0,
      hsnCode: map['hsnCode'] as String?,
      taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 0.0,
      isActive: map['isActive'] == null || map['isActive'] == 1 || map['isActive'] == true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}
