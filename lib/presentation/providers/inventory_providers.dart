import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/accounting/manufacturing_journal_engine.dart';
import '../../data/local/audit_service.dart';
import '../../data/local/drift_inventory_repository.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/stock_ledger_model.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';

final manufacturingJournalEngineProvider = Provider<ManufacturingJournalEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ManufacturingJournalEngine(db, AuditService(db));
});

final inventoryRepositoryProvider = Provider<DriftInventoryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final profile = ref.watch(userProfileProvider);
  return DriftInventoryRepository(
    db: db,
    auditService: AuditService(db),
    currentCompanyId: profile.activeCompanyId,
    currentUserId: profile.id,
    currentRole: profile.role,
  );
});

class InventorySearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final inventorySearchQueryProvider =
    NotifierProvider<InventorySearchQueryNotifier, String>(
  InventorySearchQueryNotifier.new,
);

class InventoryLowStockFilterNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setFilter(bool value) {
    state = value;
  }
}

final inventoryLowStockFilterProvider =
    NotifierProvider<InventoryLowStockFilterNotifier, bool>(
  InventoryLowStockFilterNotifier.new,
);

final inventoryItemsListProvider = FutureProvider<List<InventoryItem>>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  final search = ref.watch(inventorySearchQueryProvider);
  final lowStockOnly = ref.watch(inventoryLowStockFilterProvider);
  return await repo.getItems(
    searchQuery: search,
    lowStockOnly: lowStockOnly ? true : null,
  );
});

final inventoryValuationProvider = FutureProvider<(int, double, int)>((ref) async {
  final repo = ref.watch(inventoryRepositoryProvider);
  return await repo.getInventoryValuation();
});

class InventoryController extends Notifier<void> {
  @override
  void build() {}

  Future<InventoryItem> addItem(InventoryItem item) async {
    final repo = ref.read(inventoryRepositoryProvider);
    final result = await repo.addItem(item);
    ref.invalidate(inventoryItemsListProvider);
    ref.invalidate(inventoryValuationProvider);
    return result;
  }

  Future<void> updateItem(InventoryItem item) async {
    final repo = ref.read(inventoryRepositoryProvider);
    await repo.updateItem(item);
    ref.invalidate(inventoryItemsListProvider);
    ref.invalidate(inventoryValuationProvider);
  }

  Future<void> adjustStock({
    required String itemId,
    required double quantityDelta,
    required StockTransactionType type,
    String? note,
  }) async {
    final repo = ref.read(inventoryRepositoryProvider);
    await repo.adjustStock(
      itemId: itemId,
      quantityDelta: quantityDelta,
      type: type,
      note: note,
    );
    ref.invalidate(inventoryItemsListProvider);
    ref.invalidate(inventoryValuationProvider);
  }
}

final inventoryControllerProvider =
    NotifierProvider<InventoryController, void>(InventoryController.new);
