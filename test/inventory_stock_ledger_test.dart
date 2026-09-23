import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_inventory_repository.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/models/stock_ledger_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;
  late DriftInventoryRepository inventoryRepo;

  const testCompanyId = 'cmp_inv_1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    inventoryRepo = DriftInventoryRepository(
      db: db,
      auditService: auditService,
      currentCompanyId: testCompanyId,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Item Master & Inventory Stock Ledger (FR-INT-01, FR-INT-02) Tests', () {
    test('Creating items and querying SKU lists and low stock items', () async {
      final now = DateTime.now();

      final item1 = InventoryItem(
        id: 'item_1',
        companyId: testCompanyId,
        sku: 'SKU-LAPTOP-01',
        name: 'Pro Laptop 15-inch',
        sellingPriceInCents: 120000,
        purchasePriceInCents: 90000,
        currentStockQuantity: 15.0,
        minimumStockAlert: 5.0,
        unit: 'PCS',
        taxRatePercent: 18.0,
        hsnCode: '84713010',
        createdAt: now,
        updatedAt: now,
      );

      final item2 = InventoryItem(
        id: 'item_2',
        companyId: testCompanyId,
        sku: 'SKU-MOUSE-02',
        name: 'Wireless Mouse',
        sellingPriceInCents: 3000,
        purchasePriceInCents: 1500,
        currentStockQuantity: 3.0,
        minimumStockAlert: 10.0,
        unit: 'PCS',
        taxRatePercent: 18.0,
        hsnCode: '84716060',
        createdAt: now,
        updatedAt: now,
      );

      await inventoryRepo.addItem(item1);
      await inventoryRepo.addItem(item2);

      // Verify listing
      final items = await inventoryRepo.getItems();
      expect(items.length, equals(2));

      // Verify low stock query returns item2 because currentStockQuantity (3) <= minimumStockAlert (10)
      final lowStock = await inventoryRepo.getItems(lowStockOnly: true);
      expect(lowStock.length, equals(1));
      expect(lowStock.first.sku, equals('SKU-MOUSE-02'));
    });

    test('Stock Adjustment updates current stock and creates audited stock ledger entry', () async {
      final now = DateTime.now();

      final item = InventoryItem(
        id: 'item_adj_1',
        companyId: testCompanyId,
        sku: 'SKU-CABLE-01',
        name: 'USB-C Fast Cable',
        sellingPriceInCents: 1000,
        purchasePriceInCents: 400,
        currentStockQuantity: 100.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      );
      await inventoryRepo.addItem(item);

      // Perform stock adjustment: +20
      await inventoryRepo.adjustStock(
        itemId: 'item_adj_1',
        quantityDelta: 20.0,
        type: StockTransactionType.adjustment,
        note: 'Annual physical inventory count audit',
      );

      final updated = await inventoryRepo.getItemById('item_adj_1');
      expect(updated.currentStockQuantity, equals(120.0));

      final movements = await inventoryRepo.getStockLedger('item_adj_1');
      expect(movements.any((m) => m.quantity == 20.0 && m.transactionType == StockTransactionType.adjustment), isTrue);
    });

    test('Total inventory valuation calculation in cents', () async {
      final now = DateTime.now();

      final item1 = InventoryItem(
        id: 'val_1',
        companyId: testCompanyId,
        sku: 'SKU-VAL-1',
        name: 'Item A',
        sellingPriceInCents: 10000,
        purchasePriceInCents: 5000, // 10 * 50.00 = 500.00 = 50000 cents
        currentStockQuantity: 10.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      );

      final item2 = InventoryItem(
        id: 'val_2',
        companyId: testCompanyId,
        sku: 'SKU-VAL-2',
        name: 'Item B',
        sellingPriceInCents: 20000,
        purchasePriceInCents: 12000, // 5 * 120.00 = 600.00 = 60000 cents
        currentStockQuantity: 5.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      );

      await inventoryRepo.addItem(item1);
      await inventoryRepo.addItem(item2);

      final (totalItems, totalStockQty, totalValuationInCents) = await inventoryRepo.getInventoryValuation();
      expect(totalItems, equals(2));
      expect(totalStockQty, equals(15.0));
      expect(totalValuationInCents, equals(110000)); // 50000 + 60000 = 110000 cents
    });
  });
}
