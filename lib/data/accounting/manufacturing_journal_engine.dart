import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/audit_log_model.dart';
import '../models/manufacturing_bom_model.dart';

import '../models/voucher_model.dart';

class ManufacturingExecutionResult {
  final bool success;
  final String? errorMessage;
  final String? voucherId;
  final String? voucherNumber;
  final int totalCostInCents;
  final int unitCostInCents;
  final List<String> rawMaterialsConsumedSummary;

  const ManufacturingExecutionResult({
    required this.success,
    this.errorMessage,
    this.voucherId,
    this.voucherNumber,
    this.totalCostInCents = 0,
    this.unitCostInCents = 0,
    this.rawMaterialsConsumedSummary = const [],
  });
}

class ManufacturingJournalEngine {
  final AppDatabase _db;
  final AuditService _auditService;

  ManufacturingJournalEngine(this._db, this._auditService);

  /// Executes a production run based on a Bill of Materials
  Future<ManufacturingExecutionResult> executeProductionRun({
    required BillOfMaterials bom,
    required double productionQuantity,
    required String companyId,
    required String userId,
    DateTime? productionDate,
  }) async {
    if (productionQuantity <= 0) {
      return const ManufacturingExecutionResult(
        success: false,
        errorMessage: 'Production quantity must be greater than zero.',
      );
    }

    final date = productionDate ?? DateTime.now();

    return await _db.transaction(() async {
      // 1. Check stock availability for all raw materials
      final consumptionSummary = <String>[];
      final scaleFactor = productionQuantity / (bom.outputQuantity > 0 ? bom.outputQuantity : 1.0);

      for (final raw in bom.rawMaterials) {
        final requiredQty = raw.quantityRequired * scaleFactor * (1.0 + (raw.wastagePercentage / 100.0));
        
        final itemQuery = await (_db.select(_db.inventoryItems)
              ..where((tbl) => tbl.id.equals(raw.rawMaterialItemId)))
            .getSingleOrNull();

        if (itemQuery != null) {
          if (itemQuery.currentStockQuantity < requiredQty) {
            return ManufacturingExecutionResult(
              success: false,
              errorMessage:
                  'Insufficient stock for raw material "${raw.rawMaterialName}" (${raw.rawMaterialSku}). Available: ${itemQuery.currentStockQuantity} ${raw.unit}, Required: $requiredQty ${raw.unit}.',
            );
          }
        }
      }

      // 2. Compute total production cost
      final totalRawCost = (bom.totalRawMaterialsCostInCents * scaleFactor).round();
      final totalOverhead = (bom.totalOverheadsCostInCents * scaleFactor).round();
      final totalCostInCents = totalRawCost + totalOverhead;
      final unitCostInCents = (totalCostInCents / productionQuantity).round();

      final voucherNumber = 'MFG-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
      final voucherId = 'vch_mfg_${DateTime.now().millisecondsSinceEpoch}';

      // 3. Deduct raw materials and write stock ledger
      for (final raw in bom.rawMaterials) {
        final requiredQty = raw.quantityRequired * scaleFactor * (1.0 + (raw.wastagePercentage / 100.0));

        // Decrement item current stock
        await _db.customUpdate(
          'UPDATE inventory_items SET current_stock_quantity = current_stock_quantity - ? WHERE id = ?',
          variables: [Variable.withReal(requiredQty), Variable.withString(raw.rawMaterialItemId)],
          updates: {_db.inventoryItems},
        );

        // Record outward movement in stock ledger
        await _db.into(_db.stockLedger).insert(
              StockLedgerCompanion.insert(
                id: 'stk_${DateTime.now().millisecondsSinceEpoch}_${raw.rawMaterialItemId}',
                itemId: raw.rawMaterialItemId,
                companyId: Value(companyId),
                voucherId: Value(voucherId),
                transactionType: 'adjustment',
                quantity: -requiredQty,
                unitCostInCents: Value(raw.unitCostInCents),
                totalCostInCents: Value((requiredQty * raw.unitCostInCents).round()),
                runningStockQuantity: Value(0.0),
                date: date,
                note: Value('Consumed in BOM Production ($productionQuantity ${bom.outputUnit} ${bom.finishedGoodsName})'),
                createdAt: Value(DateTime.now()),
              ),
            );

        consumptionSummary.add('${raw.rawMaterialName}: ${requiredQty.toStringAsFixed(2)} ${raw.unit}');
      }

      // 4. Increase finished goods current stock
      await _db.customUpdate(
        'UPDATE inventory_items SET current_stock_quantity = current_stock_quantity + ?, purchase_price_in_cents = ? WHERE id = ?',
        variables: [
          Variable.withReal(productionQuantity),
          Variable.withInt(unitCostInCents),
          Variable.withString(bom.finishedGoodsItemId),
        ],
        updates: {_db.inventoryItems},
      );

      // Record inward movement for finished goods
      await _db.into(_db.stockLedger).insert(
            StockLedgerCompanion.insert(
              id: 'stk_${DateTime.now().millisecondsSinceEpoch}_${bom.finishedGoodsItemId}',
              itemId: bom.finishedGoodsItemId,
              companyId: Value(companyId),
              voucherId: Value(voucherId),
              transactionType: 'adjustment',
              quantity: productionQuantity,
              unitCostInCents: Value(unitCostInCents),
              totalCostInCents: Value(totalCostInCents),
              runningStockQuantity: Value(0.0),
              date: date,
              note: Value('Produced via BOM (${bom.bomName})'),
              createdAt: Value(DateTime.now()),
            ),
          );

      // 5. Create Manufacturing Voucher
      await _db.into(_db.vouchers).insert(
            VouchersCompanion.insert(
              id: voucherId,
              companyId: Value(companyId),
              voucherNumber: voucherNumber,
              type: VoucherType.journal.name,
              date: date,
              status: Value(VoucherStatus.posted.name),
              subtotalInCents: Value(totalCostInCents),
              taxInCents: const Value(0),
              discountInCents: const Value(0),
              totalAmountInCents: Value(totalCostInCents),
              narration: Value(
                'Manufacturing Journal: Produced $productionQuantity ${bom.outputUnit} of ${bom.finishedGoodsName} (${bom.finishedGoodsSku}) via BOM "${bom.bomName}". Unit Cost: ₹${(unitCostInCents / 100.0).toStringAsFixed(2)}.',
              ),
              itemsJson: Value(
                jsonEncode([
                  {
                    'itemId': bom.finishedGoodsItemId,
                    'itemName': bom.finishedGoodsName,
                    'sku': bom.finishedGoodsSku,
                    'quantity': productionQuantity,
                    'unitRateInCents': unitCostInCents,
                    'totalInCents': totalCostInCents,
                  }
                ]),
              ),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 6. Audit Trail Logging
      await _auditService.recordLog(
        companyId: companyId,
        userId: userId,
        action: AuditAction.insert,
        entityType: 'MANUFACTURING_JOURNAL',
        entityId: voucherId,
        newState: {
          'voucherNumber': voucherNumber,
          'bomId': bom.id,
          'bomName': bom.bomName,
          'finishedGood': bom.finishedGoodsName,
          'productionQty': productionQuantity,
          'totalCostInCents': totalCostInCents,
          'unitCostInCents': unitCostInCents,
        },
      );

      return ManufacturingExecutionResult(
        success: true,
        voucherId: voucherId,
        voucherNumber: voucherNumber,
        totalCostInCents: totalCostInCents,
        unitCostInCents: unitCostInCents,
        rawMaterialsConsumedSummary: consumptionSummary,
      );
    });
  }
}
