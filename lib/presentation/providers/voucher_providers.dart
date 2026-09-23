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

final vouchersListProvider = FutureProvider.family<List<VoucherModel>, VoucherType?>((ref, type) async {
  final repo = ref.watch(voucherRepositoryProvider);
  return await repo.getVouchers(type: type);
});

final ordersAndEstimatesProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final repo = ref.watch(voucherRepositoryProvider);
  final allVouchers = await repo.getVouchers();
  return allVouchers.where((v) => v.type.isOrderOrEstimate).toList();
});

class VoucherController extends Notifier<void> {
  @override
  void build() {}

  Future<VoucherModel> createVoucher(VoucherModel voucher) async {
    final repo = ref.read(voucherRepositoryProvider);
    final posted = await repo.createVoucher(voucher);
    ref.invalidate(vouchersListProvider);
    ref.invalidate(ordersAndEstimatesProvider);
    ref.invalidate(partyListProvider);
    ref.invalidate(businessSummaryProvider);
    return posted;
  }

  Future<VoucherModel> convertToInvoice(String orderOrEstimateId) async {
    final repo = ref.read(voucherRepositoryProvider);
    final invoice = await repo.convertToInvoice(orderOrEstimateId);
    ref.invalidate(vouchersListProvider);
    ref.invalidate(ordersAndEstimatesProvider);
    ref.invalidate(partyListProvider);
    ref.invalidate(businessSummaryProvider);
    return invoice;
  }

  Future<void> voidVoucher(String voucherId) async {
    final repo = ref.read(voucherRepositoryProvider);
    await repo.voidVoucher(voucherId);
    ref.invalidate(vouchersListProvider);
    ref.invalidate(ordersAndEstimatesProvider);
    ref.invalidate(partyListProvider);
    ref.invalidate(businessSummaryProvider);
  }
}

final voucherControllerProvider =
    NotifierProvider<VoucherController, void>(VoucherController.new);
