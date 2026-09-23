import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/models/stock_ledger_model.dart';
import 'package:ledger_pulse/data/reporting/inventory_report_engine.dart';

void main() {
  group('Inventory Report Engine Tests (FR-RPT-01, FR-INT-08)', () {
    late List<InventoryItem> sampleItems;
    late List<StockLedgerEntry> sampleLedgerEntries;

    setUp(() {
      sampleItems = [
        InventoryItem(
          id: 'item_1',
          companyId: 'cmp_1',
          sku: 'SKU-001',
          name: 'Steel Sheet 2mm',
          unit: 'SHEET',
          purchasePriceInCents: 120000, // ₹1,200.00
          sellingPriceInCents: 180000, // ₹1,800.00
          currentStockQuantity: 50.0,
          minimumStockAlert: 20.0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        InventoryItem(
          id: 'item_2',
          companyId: 'cmp_1',
          sku: 'SKU-002',
          name: 'Copper Rivets',
          unit: 'BOX',
          purchasePriceInCents: 35000, // ₹350.00
          sellingPriceInCents: 50000, // ₹500.00
          currentStockQuantity: 3.0, // Below minimum 10.0!
          minimumStockAlert: 10.0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ];

      sampleLedgerEntries = [
        StockLedgerEntry(
          id: 'sle_1',
          companyId: 'cmp_1',
          itemId: 'item_1',
          transactionType: StockTransactionType.inward,
          quantity: 60.0,
          unitCostInCents: 120000,
          totalCostInCents: 7200000,
          runningStockQuantity: 60.0,
          date: DateTime(2026, 9, 1),
          createdAt: DateTime(2026, 9, 1),
        ),
        StockLedgerEntry(
          id: 'sle_2',
          companyId: 'cmp_1',
          itemId: 'item_1',
          transactionType: StockTransactionType.outward,
          quantity: 10.0,
          unitCostInCents: 120000,
          totalCostInCents: 1200000,
          runningStockQuantity: 50.0,
          date: DateTime(2026, 9, 10),
          createdAt: DateTime(2026, 9, 10),
        ),
      ];
    });

    test('generateStockSummary computes valuation and flags status properly', () {
      final summary = InventoryReportEngine.generateStockSummary(items: sampleItems);

      expect(summary.metadata.id, equals('rpt_stock_summary'));
      expect(summary.rows.length, equals(2));

      final row1 = summary.rows.first;
      expect(row1.get('sku'), equals('SKU-001'));
      expect(row1.get('status'), equals('IN STOCK'));

      final row2 = summary.rows[1];
      expect(row2.get('sku'), equals('SKU-002'));
      expect(row2.get('status'), equals('LOW STOCK'));

      expect(summary.summary['totalItemsCount'], equals(2));
    });

    test('generateItemStockLedger maps audit trail of inward and outward stock movements', () {
      final ledger = InventoryReportEngine.generateItemStockLedger(
        item: sampleItems.first,
        entries: sampleLedgerEntries,
      );

      expect(ledger.metadata.id, equals('rpt_item_ledger_item_1'));
      expect(ledger.rows.length, equals(2));
      expect(ledger.rows.first.get('inward'), equals('60.0'));
      expect(ledger.rows.last.get('outward'), equals('10.0'));
      expect(ledger.rows.last.get('balance'), equals('50.0'));
    });

    test('generateLowStockRegister flags SKUs requiring replenishment with calculated reorder deficit', () {
      final register = InventoryReportEngine.generateLowStockRegister(items: sampleItems);

      expect(register.metadata.id, equals('rpt_low_stock'));
      expect(register.rows.length, equals(1));

      final alertRow = register.rows.first;
      expect(alertRow.get('sku'), equals('SKU-002'));
      expect(alertRow.get('current'), equals('3.0'));
      expect(alertRow.get('minimum'), equals('10.0'));
      expect(alertRow.get('reorderDeficit'), equals('7.0')); // 10 - 3 = 7
    });
  });
}
