import 'package:drift/drift.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/audit_log_model.dart';
import '../models/inventory_item_model.dart';
import '../models/rbac_model.dart';
import '../models/stock_ledger_model.dart';
import '../security/access_control_service.dart';

class DriftInventoryRepository {
  final AppDatabase _db;
  final AuditService _auditService;
  String _currentCompanyId;
  String _currentUserId;
  Role _currentRole;

  DriftInventoryRepository({
    required AppDatabase db,
    AuditService? auditService,
    String currentCompanyId = 'cmp_default',
    String currentUserId = 'usr_default',
    Role currentRole = Role.admin,
  })  : _db = db,
        _auditService = auditService ?? AuditService(db),
        _currentCompanyId = currentCompanyId,
        _currentUserId = currentUserId,
        _currentRole = currentRole;

  void setContext({
    String? companyId,
    String? userId,
    Role? role,
  }) {
    if (companyId != null) _currentCompanyId = companyId;
    if (userId != null) _currentUserId = userId;
    if (role != null) _currentRole = role;
  }

  Future<List<InventoryItem>> getItems({
    String? searchQuery,
    bool? lowStockOnly,
  }) async {
    final query = _db.select(_db.inventoryItems)
      ..where((t) => t.companyId.equals(_currentCompanyId) & t.isActive.equals(true))
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    final rows = await query.get();
    var list = rows.map((r) => InventoryItem(
      id: r.id,
      companyId: r.companyId,
      sku: r.sku,
      name: r.name,
      description: r.description,
      unit: r.unit,
      purchasePriceInCents: r.purchasePriceInCents,
      sellingPriceInCents: r.sellingPriceInCents,
      currentStockQuantity: r.currentStockQuantity,
      minimumStockAlert: r.minimumStockAlert,
      hsnCode: r.hsnCode,
      taxRatePercent: r.taxRatePercent,
      isActive: r.isActive,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    )).toList();

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      list = list.where((i) => i.name.toLowerCase().contains(q) || i.sku.toLowerCase().contains(q)).toList();
    }

    if (lowStockOnly == true) {
      list = list.where((i) => i.isLowStock).toList();
    }

    return list;
  }

  Future<InventoryItem> getItemById(String itemId) async {
    final row = await (_db.select(_db.inventoryItems)
          ..where((t) => t.id.equals(itemId) & t.companyId.equals(_currentCompanyId)))
        .getSingleOrNull();

    if (row == null) {
      throw Exception('Item not found: $itemId');
    }

    return InventoryItem(
      id: row.id,
      companyId: row.companyId,
      sku: row.sku,
      name: row.name,
      description: row.description,
      unit: row.unit,
      purchasePriceInCents: row.purchasePriceInCents,
      sellingPriceInCents: row.sellingPriceInCents,
      currentStockQuantity: row.currentStockQuantity,
      minimumStockAlert: row.minimumStockAlert,
      hsnCode: row.hsnCode,
      taxRatePercent: row.taxRatePercent,
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Future<InventoryItem> addItem(InventoryItem item) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.createSupplierEntry);

    await _db.into(_db.inventoryItems).insertOnConflictUpdate(
          InventoryItemsCompanion.insert(
            id: item.id,
            companyId: Value(_currentCompanyId),
            sku: item.sku,
            name: item.name,
            description: Value(item.description),
            unit: Value(item.unit),
            purchasePriceInCents: Value(item.purchasePriceInCents),
            sellingPriceInCents: Value(item.sellingPriceInCents),
            currentStockQuantity: Value(item.currentStockQuantity),
            minimumStockAlert: Value(item.minimumStockAlert),
            hsnCode: Value(item.hsnCode),
            taxRatePercent: Value(item.taxRatePercent),
            isActive: Value(item.isActive),
            createdAt: Value(item.createdAt),
            updatedAt: Value(item.updatedAt),
          ),
        );

    // Initial stock ledger entry if starting stock > 0
    if (item.currentStockQuantity > 0) {
      await _db.into(_db.stockLedger).insert(
            StockLedgerCompanion.insert(
              id: 'stk_init_${item.id}',
              companyId: Value(_currentCompanyId),
              itemId: item.id,
              transactionType: StockTransactionType.inward.name,
              quantity: item.currentStockQuantity,
              unitCostInCents: Value(item.purchasePriceInCents),
              totalCostInCents: Value((item.currentStockQuantity * item.purchasePriceInCents).toInt()),
              runningStockQuantity: Value(item.currentStockQuantity),
              date: item.createdAt,
              note: const Value('Initial stock opening balance'),
            ),
          );
    }

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'inventory_item',
      entityId: item.id,
      action: AuditAction.insert,
      newState: item.toMap(),
    );

    return item;
  }

  Future<void> updateItem(InventoryItem item) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.updateEntry);

    final existing = await getItemById(item.id);

    await (_db.update(_db.inventoryItems)..where((t) => t.id.equals(item.id))).write(
      InventoryItemsCompanion(
        sku: Value(item.sku),
        name: Value(item.name),
        description: Value(item.description),
        unit: Value(item.unit),
        purchasePriceInCents: Value(item.purchasePriceInCents),
        sellingPriceInCents: Value(item.sellingPriceInCents),
        minimumStockAlert: Value(item.minimumStockAlert),
        hsnCode: Value(item.hsnCode),
        taxRatePercent: Value(item.taxRatePercent),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'inventory_item',
      entityId: item.id,
      action: AuditAction.update,
      oldState: existing.toMap(),
      newState: item.toMap(),
    );
  }

  Future<void> adjustStock({
    required String itemId,
    required double quantityDelta,
    required StockTransactionType type,
    String? note,
  }) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.updateEntry);

    final item = await getItemById(itemId);
    final newStock = item.currentStockQuantity + quantityDelta;

    await (_db.update(_db.inventoryItems)..where((t) => t.id.equals(itemId))).write(
      InventoryItemsCompanion(
        currentStockQuantity: Value(newStock),
        updatedAt: Value(DateTime.now()),
      ),
    );

    await _db.into(_db.stockLedger).insert(
          StockLedgerCompanion.insert(
            id: 'stk_adj_${DateTime.now().millisecondsSinceEpoch}',
            companyId: Value(_currentCompanyId),
            itemId: itemId,
            transactionType: type.name,
            quantity: quantityDelta.abs(),
            unitCostInCents: Value(item.purchasePriceInCents),
            totalCostInCents: Value((quantityDelta.abs() * item.purchasePriceInCents).toInt()),
            runningStockQuantity: Value(newStock),
            date: DateTime.now(),
            note: Value(note ?? 'Manual stock adjustment'),
          ),
        );
  }

  Future<List<StockLedgerEntry>> getStockLedger(String itemId) async {
    final query = _db.select(_db.stockLedger)
      ..where((t) => t.itemId.equals(itemId) & t.companyId.equals(_currentCompanyId))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt)]);

    final rows = await query.get();
    return rows.map((r) => StockLedgerEntry(
      id: r.id,
      companyId: r.companyId,
      itemId: r.itemId,
      voucherId: r.voucherId,
      transactionType: StockTransactionType.values.byName(r.transactionType),
      quantity: r.quantity,
      unitCostInCents: r.unitCostInCents,
      totalCostInCents: r.totalCostInCents,
      runningStockQuantity: r.runningStockQuantity,
      date: r.date,
      note: r.note,
      createdAt: r.createdAt,
    )).toList();
  }

  Future<(int totalItems, double totalStockQty, int totalValuationInCents)> getInventoryValuation() async {
    final items = await getItems();
    int totalItems = items.length;
    double totalStockQty = 0;
    int totalValuation = 0;

    for (final item in items) {
      totalStockQty += item.currentStockQuantity;
      totalValuation += (item.currentStockQuantity * item.purchasePriceInCents).toInt();
    }

    return (totalItems, totalStockQty, totalValuation);
  }
}
