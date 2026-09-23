import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../models/inventory_item_model.dart';
import '../models/stock_ledger_model.dart';
import 'report_models.dart';

class InventoryReportEngine {
  /// Generates Stock Summary valuation report
  static ReportData generateStockSummary({
    required List<InventoryItem> items,
  }) {
    int totalCostValuationCents = 0;
    int totalSellingValuationCents = 0;
    double totalUnits = 0.0;

    final rows = items.map((item) {
      final costValuation = (item.purchasePriceInCents * item.currentStockQuantity).round();
      final sellingValuation = (item.sellingPriceInCents * item.currentStockQuantity).round();

      totalCostValuationCents += costValuation;
      totalSellingValuationCents += sellingValuation;
      totalUnits += item.currentStockQuantity;

      return ReportRow({
        'sku': item.sku,
        'name': item.name,
        'unit': item.unit,
        'stock': item.currentStockQuantity.toStringAsFixed(1),
        'costPrice': CurrencyFormatter.format(item.purchasePriceInCents),
        'sellingPrice': CurrencyFormatter.format(item.sellingPriceInCents),
        'totalValuation': CurrencyFormatter.format(costValuation),
        'status': item.currentStockQuantity <= item.minimumStockAlert ? 'LOW STOCK' : 'IN STOCK',
      });
    }).toList();

    return ReportData(
      metadata: const ReportMetadata(
        id: 'rpt_stock_summary',
        title: 'Stock Summary & Valuation',
        category: ReportCategory.inventoryWarehouse,
        description: 'Comprehensive inventory valuation report across all SKU holdings.',
      ),
      columns: const [
        ReportColumn(key: 'sku', label: 'SKU'),
        ReportColumn(key: 'name', label: 'Item Name'),
        ReportColumn(key: 'stock', label: 'Current Qty', isNumeric: true),
        ReportColumn(key: 'unit', label: 'Unit'),
        ReportColumn(key: 'costPrice', label: 'Avg Cost', isNumeric: true, isCurrency: true),
        ReportColumn(key: 'sellingPrice', label: 'Selling Rate', isNumeric: true, isCurrency: true),
        ReportColumn(key: 'totalValuation', label: 'Valuation (Cost)', isNumeric: true, isCurrency: true),
        ReportColumn(key: 'status', label: 'Status'),
      ],
      rows: rows,
      summary: {
        'totalHoldingValuation': CurrencyFormatter.format(totalCostValuationCents),
        'totalPotentialRevenue': CurrencyFormatter.format(totalSellingValuationCents),
        'totalItemsCount': items.length,
        'totalUnitsQuantity': totalUnits.toStringAsFixed(1),
      },
      generatedAt: DateTime.now(),
    );
  }

  /// Generates Item-wise Stock Ledger
  static ReportData generateItemStockLedger({
    required InventoryItem item,
    required List<StockLedgerEntry> entries,
  }) {
    final itemEntries = entries.where((e) => e.itemId == item.id).toList();

    final rows = itemEntries.map((e) {
      final isInward = e.transactionType == StockTransactionType.inward;
      final isOutward = e.transactionType == StockTransactionType.outward;

      return ReportRow({
        'date': DateFormatter.formatShortDate(e.date),
        'voucher': e.voucherId ?? 'Stock Adjustment',
        'type': e.transactionType.displayName,
        'inward': isInward ? e.quantity.toStringAsFixed(1) : '-',
        'outward': isOutward ? e.quantity.toStringAsFixed(1) : '-',
        'rate': CurrencyFormatter.format(e.unitCostInCents),
        'total': CurrencyFormatter.format(e.totalCostInCents),
        'balance': e.runningStockQuantity.toStringAsFixed(1),
      });
    }).toList();

    return ReportData(
      metadata: ReportMetadata(
        id: 'rpt_item_ledger_${item.id}',
        title: 'Stock Ledger: ${item.name} (${item.sku})',
        category: ReportCategory.inventoryWarehouse,
        description: 'Complete audit trail of inward, outward, and adjustment inventory movements.',
      ),
      columns: const [
        ReportColumn(key: 'date', label: 'Date'),
        ReportColumn(key: 'voucher', label: 'Voucher Ref'),
        ReportColumn(key: 'type', label: 'Movement'),
        ReportColumn(key: 'inward', label: 'Inward (+)', isNumeric: true),
        ReportColumn(key: 'outward', label: 'Outward (-)', isNumeric: true),
        ReportColumn(key: 'rate', label: 'Unit Rate', isNumeric: true, isCurrency: true),
        ReportColumn(key: 'total', label: 'Total Value', isNumeric: true, isCurrency: true),
        ReportColumn(key: 'balance', label: 'Running Balance', isNumeric: true),
      ],
      rows: rows,
      generatedAt: DateTime.now(),
    );
  }

  /// Generates Low Stock Register
  static ReportData generateLowStockRegister({
    required List<InventoryItem> items,
  }) {
    final lowItems = items.where((i) => i.currentStockQuantity <= i.minimumStockAlert).toList();

    final rows = lowItems.map((item) {
      final deficit = (item.minimumStockAlert - item.currentStockQuantity).clamp(0.0, 99999.0);
      return ReportRow({
        'sku': item.sku,
        'name': item.name,
        'current': item.currentStockQuantity.toStringAsFixed(1),
        'minimum': item.minimumStockAlert.toStringAsFixed(1),
        'reorderDeficit': deficit.toStringAsFixed(1),
        'unit': item.unit,
        'costToRestock': CurrencyFormatter.format((item.purchasePriceInCents * deficit).round()),
      });
    }).toList();

    return ReportData(
      metadata: const ReportMetadata(
        id: 'rpt_low_stock',
        title: 'Low Stock & Reorder Alert Register',
        category: ReportCategory.inventoryWarehouse,
        description: 'SKUs at or below safety reorder threshold requiring warehouse replenishment.',
      ),
      columns: const [
        ReportColumn(key: 'sku', label: 'SKU'),
        ReportColumn(key: 'name', label: 'Item Name'),
        ReportColumn(key: 'current', label: 'Current Qty', isNumeric: true),
        ReportColumn(key: 'minimum', label: 'Threshold', isNumeric: true),
        ReportColumn(key: 'reorderDeficit', label: 'Reorder Deficit', isNumeric: true),
        ReportColumn(key: 'unit', label: 'Unit'),
        ReportColumn(key: 'costToRestock', label: 'Est. Cost', isNumeric: true, isCurrency: true),
      ],
      rows: rows,
      summary: {
        'totalLowStockSKUs': lowItems.length,
      },
      generatedAt: DateTime.now(),
    );
  }
}
