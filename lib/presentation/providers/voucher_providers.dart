import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/accounting/voucher_posting_engine.dart';
import '../../data/local/audit_service.dart';
import '../../data/local/drift_voucher_repository.dart';
import '../../data/models/voucher_model.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';

final voucherPostingEngineProvider = Provider<VoucherPostingEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return VoucherPostingEngine(db, AuditService(db));
});

final voucherRepositoryProvider = Provider<DriftVoucherRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final profile = ref.watch(userProfileProvider);
  final engine = ref.watch(voucherPostingEngineProvider);
  return DriftVoucherRepository(
    db: db,
    postingEngine: engine,
    auditService: AuditService(db),
    currentCompanyId: profile.activeCompanyId,
    currentUserId: profile.id,
    currentRole: profile.role,
  );
});

final nextVoucherNumberProvider = FutureProvider.family<String, VoucherType>((ref, type) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.generateNextVoucherNumber(type);
});

final vouchersListProvider = FutureProvider.family<List<VoucherModel>, VoucherType?>((ref, type) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: type);
});

final salesInvoicesListProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: VoucherType.sales);
});

final salesOrdersListProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: VoucherType.salesOrder);
});

final estimatesListProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: VoucherType.estimate);
});

final purchasesListProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: VoucherType.purchase);
});

final ordersAndEstimatesProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  final allVouchers = await repo.getVouchers();
  return allVouchers.where((v) => v.type.isOrderOrEstimate).toList();
});

final draftAndHeldVouchersProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  final allVouchers = await repo.getVouchers();
  return allVouchers
      .where((v) => v.status == VoucherStatus.draft || v.status == VoucherStatus.onHold)
      .toList();
});

final receivablesVouchersProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: VoucherType.sales, status: VoucherStatus.posted);
});

final payablesVouchersProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: VoucherType.purchase, status: VoucherStatus.posted);
});

class VoucherController extends Notifier<void> {
  @override
  void build() {}

  void _invalidateAll() {
    ref.invalidate(vouchersListProvider);
    ref.invalidate(salesInvoicesListProvider);
    ref.invalidate(salesOrdersListProvider);
    ref.invalidate(estimatesListProvider);
    ref.invalidate(purchasesListProvider);
    ref.invalidate(ordersAndEstimatesProvider);
    ref.invalidate(draftAndHeldVouchersProvider);
    ref.invalidate(receivablesVouchersProvider);
    ref.invalidate(payablesVouchersProvider);
    ref.invalidate(partyListProvider);
    ref.invalidate(businessSummaryProvider);
    ref.invalidate(nextVoucherNumberProvider);
  }

  Future<VoucherModel> createVoucher(VoucherModel voucher) async {
    final repo = ref.read(voucherRepositoryProvider);
    final posted = await repo.createVoucher(voucher);
    _invalidateAll();
    return posted;
  }

  Future<VoucherModel> convertEstimateToSalesOrder(String estimateId) async {
    final repo = ref.read(voucherRepositoryProvider);
    final order = await repo.convertEstimateToSalesOrder(estimateId);
    _invalidateAll();
    return order;
  }

  Future<VoucherModel> convertEstimateToSalesInvoice(String estimateId) async {
    final repo = ref.read(voucherRepositoryProvider);
    final invoice = await repo.convertEstimateToSalesInvoice(estimateId);
    _invalidateAll();
    return invoice;
  }

  Future<VoucherModel> convertSalesOrderToSalesInvoice(String salesOrderId) async {
    final repo = ref.read(voucherRepositoryProvider);
    final invoice = await repo.convertSalesOrderToSalesInvoice(salesOrderId);
    _invalidateAll();
    return invoice;
  }

  Future<VoucherModel> convertToInvoice(String orderOrEstimateId) async {
    final repo = ref.read(voucherRepositoryProvider);
    final invoice = await repo.convertToInvoice(orderOrEstimateId);
    _invalidateAll();
    return invoice;
  }

  Future<void> voidVoucher(String voucherId) async {
    final repo = ref.read(voucherRepositoryProvider);
    await repo.voidVoucher(voucherId);
    _invalidateAll();
  }
}

final voucherControllerProvider =
    NotifierProvider<VoucherController, void>(VoucherController.new);
