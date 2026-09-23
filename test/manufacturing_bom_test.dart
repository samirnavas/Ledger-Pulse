import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/manufacturing_journal_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/manufacturing_bom_model.dart';

void main() {
  group('Manufacturing Journal & BOM Tests (FR-INT-04)', () {
    late AppDatabase db;
    late AuditService auditService;
    late ManufacturingJournalEngine engine;
    const companyId = 'cmp_mfg_01';
    const userId = 'usr_admin_01';

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      auditService = AuditService(db);
      engine = ManufacturingJournalEngine(db, auditService);

      // Seed raw materials and finished good item
      await db.into(db.inventoryItems).insert(
            InventoryItemsCompanion.insert(
              id: 'raw_wood_01',
              companyId: const Value('cmp_mfg_01'),
              sku: 'RAW-WOOD-PLK',
              name: 'Teak Wood Plank',
              currentStockQuantity: const Value(100.0),
              purchasePriceInCents: const Value(50000), // ₹500
              sellingPriceInCents: const Value(75000),
            ),
          );

      await db.into(db.inventoryItems).insert(
            InventoryItemsCompanion.insert(
              id: 'raw_screws_01',
              companyId: const Value('cmp_mfg_01'),
              sku: 'RAW-SCR-BOX',
              name: 'Industrial Screws (Pack)',
              currentStockQuantity: const Value(50.0),
              purchasePriceInCents: const Value(10000), // ₹100
              sellingPriceInCents: const Value(15000),
            ),
          );

      await db.into(db.inventoryItems).insert(
            InventoryItemsCompanion.insert(
              id: 'fg_chair_01',
              companyId: const Value('cmp_mfg_01'),
              sku: 'FG-CHAIR-01',
              name: 'Executive Ergonomic Wooden Chair',
              currentStockQuantity: const Value(0.0),
              purchasePriceInCents: const Value(0),
              sellingPriceInCents: const Value(450000), // ₹4,500
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('BOM Cost calculation accurately sums raw materials and overheads', () {
      final bom = BillOfMaterials(
        id: 'bom_chair_01',
        companyId: companyId,
        bomName: 'Standard Chair Assembly',
        finishedGoodsItemId: 'fg_chair_01',
        finishedGoodsSku: 'FG-CHAIR-01',
        finishedGoodsName: 'Executive Ergonomic Wooden Chair',
        outputQuantity: 1.0,
        outputUnit: 'PCS',
        rawMaterials: const [
          BomRawMaterialItem(
            rawMaterialItemId: 'raw_wood_01',
            rawMaterialSku: 'RAW-WOOD-PLK',
            rawMaterialName: 'Teak Wood Plank',
            quantityRequired: 4.0, // 4 planks @ ₹500 = ₹2,000 (200,000 cents)
            unit: 'PLK',
            unitCostInCents: 50000,
          ),
          BomRawMaterialItem(
            rawMaterialItemId: 'raw_screws_01',
            rawMaterialSku: 'RAW-SCR-BOX',
            rawMaterialName: 'Industrial Screws (Pack)',
            quantityRequired: 1.0, // 1 pack @ ₹100 = ₹100 (10,000 cents)
            unit: 'BOX',
            unitCostInCents: 10000,
          ),
        ],
        directLaborCostInCents: 50000, // ₹500 labor
        electricityOverheadInCents: 20000, // ₹200 electricity
        createdAt: DateTime.now(),
      );

      expect(bom.totalRawMaterialsCostInCents, equals(210000)); // ₹2,100
      expect(bom.totalOverheadsCostInCents, equals(70000));     // ₹700
      expect(bom.totalProductionCostInCents, equals(280000));   // ₹2,800
      expect(bom.unitProductionCostInCents, equals(280000));    // ₹2,800/unit
    });

    test('executeProductionRun decrements raw materials and increments finished goods atomically', () async {
      final bom = BillOfMaterials(
        id: 'bom_chair_01',
        companyId: companyId,
        bomName: 'Standard Chair Assembly',
        finishedGoodsItemId: 'fg_chair_01',
        finishedGoodsSku: 'FG-CHAIR-01',
        finishedGoodsName: 'Executive Ergonomic Wooden Chair',
        outputQuantity: 1.0,
        outputUnit: 'PCS',
        rawMaterials: const [
          BomRawMaterialItem(
            rawMaterialItemId: 'raw_wood_01',
            rawMaterialSku: 'RAW-WOOD-PLK',
            rawMaterialName: 'Teak Wood Plank',
            quantityRequired: 4.0,
            unit: 'PLK',
            unitCostInCents: 50000,
          ),
          BomRawMaterialItem(
            rawMaterialItemId: 'raw_screws_01',
            rawMaterialSku: 'RAW-SCR-BOX',
            rawMaterialName: 'Industrial Screws (Pack)',
            quantityRequired: 1.0,
            unit: 'BOX',
            unitCostInCents: 10000,
          ),
        ],
        directLaborCostInCents: 50000,
        electricityOverheadInCents: 20000,
        createdAt: DateTime.now(),
      );

      // Produce 5 chairs
      final result = await engine.executeProductionRun(
        bom: bom,
        productionQuantity: 5.0,
        companyId: companyId,
        userId: userId,
      );

      expect(result.success, isTrue);
      expect(result.voucherNumber, startsWith('MFG-'));
      expect(result.totalCostInCents, equals(1400000)); // 5 * ₹2,800 = ₹14,000
      expect(result.unitCostInCents, equals(280000));   // ₹2,800 per chair

      // Verify stock in database
      final wood = await (db.select(db.inventoryItems)..where((t) => t.id.equals('raw_wood_01'))).getSingle();
      final screws = await (db.select(db.inventoryItems)..where((t) => t.id.equals('raw_screws_01'))).getSingle();
      final chairs = await (db.select(db.inventoryItems)..where((t) => t.id.equals('fg_chair_01'))).getSingle();

      expect(wood.currentStockQuantity, equals(80.0)); // 100 - (5 * 4) = 80
      expect(screws.currentStockQuantity, equals(45.0)); // 50 - (5 * 1) = 45
      expect(chairs.currentStockQuantity, equals(5.0)); // 0 + 5 = 5
      expect(chairs.purchasePriceInCents, equals(280000)); // Updated unit cost
    });

    test('executeProductionRun rejects production when raw material stock is insufficient', () async {
      final bom = BillOfMaterials(
        id: 'bom_chair_01',
        companyId: companyId,
        bomName: 'Standard Chair Assembly',
        finishedGoodsItemId: 'fg_chair_01',
        finishedGoodsSku: 'FG-CHAIR-01',
        finishedGoodsName: 'Executive Ergonomic Wooden Chair',
        outputQuantity: 1.0,
        outputUnit: 'PCS',
        rawMaterials: const [
          BomRawMaterialItem(
            rawMaterialItemId: 'raw_wood_01',
            rawMaterialSku: 'RAW-WOOD-PLK',
            rawMaterialName: 'Teak Wood Plank',
            quantityRequired: 4.0,
            unit: 'PLK',
            unitCostInCents: 50000,
          ),
        ],
        createdAt: DateTime.now(),
      );

      // Attempt to produce 30 chairs (requires 120 planks, only 100 available)
      final result = await engine.executeProductionRun(
        bom: bom,
        productionQuantity: 30.0,
        companyId: companyId,
        userId: userId,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Insufficient stock for raw material'));

      // Check stock was not altered
      final wood = await (db.select(db.inventoryItems)..where((t) => t.id.equals('raw_wood_01'))).getSingle();
      expect(wood.currentStockQuantity, equals(100.0));
    });
  });
}
