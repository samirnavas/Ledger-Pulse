import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class BomRawMaterialItem {
  final String rawMaterialItemId;
  final String rawMaterialSku;
  final String rawMaterialName;
  final double quantityRequired;
  final String unit;
  final int unitCostInCents;
  final double wastagePercentage;

  const BomRawMaterialItem({
    required this.rawMaterialItemId,
    required this.rawMaterialSku,
    required this.rawMaterialName,
    required this.quantityRequired,
    required this.unit,
    required this.unitCostInCents,
    this.wastagePercentage = 0.0,
  });

  int get totalCostInCents {
    final effectiveQty = quantityRequired * (1.0 + (wastagePercentage / 100.0));
    return (effectiveQty * unitCostInCents).round();
  }

  Map<String, dynamic> toMap() {
    return {
      'rawMaterialItemId': rawMaterialItemId,
      'rawMaterialSku': rawMaterialSku,
      'rawMaterialName': rawMaterialName,
      'quantityRequired': quantityRequired,
      'unit': unit,
      'unitCostInCents': unitCostInCents,
      'wastagePercentage': wastagePercentage,
    };
  }

  factory BomRawMaterialItem.fromMap(Map<String, dynamic> map) {
    return BomRawMaterialItem(
      rawMaterialItemId: map['rawMaterialItemId'] ?? '',
      rawMaterialSku: map['rawMaterialSku'] ?? '',
      rawMaterialName: map['rawMaterialName'] ?? '',
      quantityRequired: (map['quantityRequired'] as num?)?.toDouble() ?? 1.0,
      unit: map['unit'] ?? 'PCS',
      unitCostInCents: map['unitCostInCents'] ?? 0,
      wastagePercentage: (map['wastagePercentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

@immutable
class BillOfMaterials {
  final String id;
  final String companyId;
  final String bomName;
  final String finishedGoodsItemId;
  final String finishedGoodsSku;
  final String finishedGoodsName;
  final double outputQuantity;
  final String outputUnit;
  final List<BomRawMaterialItem> rawMaterials;
  final int directLaborCostInCents;
  final int electricityOverheadInCents;
  final int machineOverheadInCents;
  final DateTime createdAt;

  const BillOfMaterials({
    required this.id,
    required this.companyId,
    required this.bomName,
    required this.finishedGoodsItemId,
    required this.finishedGoodsSku,
    required this.finishedGoodsName,
    this.outputQuantity = 1.0,
    this.outputUnit = 'PCS',
    required this.rawMaterials,
    this.directLaborCostInCents = 0,
    this.electricityOverheadInCents = 0,
    this.machineOverheadInCents = 0,
    required this.createdAt,
  });

  int get totalRawMaterialsCostInCents {
    return rawMaterials.fold(0, (sum, item) => sum + item.totalCostInCents);
  }

  int get totalOverheadsCostInCents {
    return directLaborCostInCents +
        electricityOverheadInCents +
        machineOverheadInCents;
  }

  int get totalProductionCostInCents {
    return totalRawMaterialsCostInCents + totalOverheadsCostInCents;
  }

  int get unitProductionCostInCents {
    if (outputQuantity <= 0) return totalProductionCostInCents;
    return (totalProductionCostInCents / outputQuantity).round();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'bomName': bomName,
      'finishedGoodsItemId': finishedGoodsItemId,
      'finishedGoodsSku': finishedGoodsSku,
      'finishedGoodsName': finishedGoodsName,
      'outputQuantity': outputQuantity,
      'outputUnit': outputUnit,
      'rawMaterials': rawMaterials.map((r) => r.toMap()).toList(),
      'directLaborCostInCents': directLaborCostInCents,
      'electricityOverheadInCents': electricityOverheadInCents,
      'machineOverheadInCents': machineOverheadInCents,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory BillOfMaterials.fromMap(Map<String, dynamic> map) {
    return BillOfMaterials(
      id: map['id'] ?? '',
      companyId: map['companyId'] ?? '',
      bomName: map['bomName'] ?? '',
      finishedGoodsItemId: map['finishedGoodsItemId'] ?? '',
      finishedGoodsSku: map['finishedGoodsSku'] ?? '',
      finishedGoodsName: map['finishedGoodsName'] ?? '',
      outputQuantity: (map['outputQuantity'] as num?)?.toDouble() ?? 1.0,
      outputUnit: map['outputUnit'] ?? 'PCS',
      rawMaterials: (map['rawMaterials'] as List<dynamic>?)
              ?.map((item) => BomRawMaterialItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
      directLaborCostInCents: map['directLaborCostInCents'] ?? 0,
      electricityOverheadInCents: map['electricityOverheadInCents'] ?? 0,
      machineOverheadInCents: map['machineOverheadInCents'] ?? 0,
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory BillOfMaterials.fromJson(String source) =>
      BillOfMaterials.fromMap(jsonDecode(source));
}
