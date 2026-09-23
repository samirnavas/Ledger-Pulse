import 'package:drift/drift.dart';
import '../accounting/voucher_posting_engine.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/audit_log_model.dart';
import '../models/rbac_model.dart';
import '../models/voucher_model.dart';
import '../security/access_control_service.dart';

class DriftVoucherRepository {
  final AppDatabase _db;
  final VoucherPostingEngine _postingEngine;
  final AuditService _auditService;
  String _currentCompanyId;
  String _currentUserId;
  Role _currentRole;

  DriftVoucherRepository({
    required AppDatabase db,
    AuditService? auditService,
    VoucherPostingEngine? postingEngine,
    String currentCompanyId = 'cmp_default',
    String currentUserId = 'usr_default',
    Role currentRole = Role.admin,
  })  : _db = db,
        _auditService = auditService ?? AuditService(db),
        _postingEngine = postingEngine ?? VoucherPostingEngine(db, auditService ?? AuditService(db)),
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

  Future<List<VoucherModel>> getVouchers({
    VoucherType? type,
    VoucherStatus? status,
    String? partyId,
  }) async {
    final query = _db.select(_db.vouchers)
      ..where((t) => t.companyId.equals(_currentCompanyId))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt)]);

    if (type != null) {
      query.where((t) => t.type.equals(type.name));
    }
    if (status != null) {
      query.where((t) => t.status.equals(status.name));
    }
    if (partyId != null) {
      query.where((t) => t.partyId.equals(partyId));
    }

    final rows = await query.get();
    return rows.map((r) => VoucherModel.fromMap({
      'id': r.id,
      'companyId': r.companyId,
      'voucherNumber': r.voucherNumber,
      'type': r.type,
      'date': r.date.toIso8601String(),
      'dueDate': r.dueDate?.toIso8601String(),
      'partyId': r.partyId,
      'partyName': r.partyName,
      'status': r.status,
      'paymentMode': r.paymentMode,
      'subtotalInCents': r.subtotalInCents,
      'taxInCents': r.taxInCents,
      'discountInCents': r.discountInCents,
      'totalAmountInCents': r.totalAmountInCents,
      'narration': r.narration,
      'referenceNumber': r.referenceNumber,
      'sourceVoucherId': r.sourceVoucherId,
      'receiptPhotoUrl': r.receiptPhotoUrl,
      'itemsJson': r.itemsJson,
      'createdAt': r.createdAt.toIso8601String(),
      'updatedAt': r.updatedAt.toIso8601String(),
    })).toList();
  }

  Future<VoucherModel> getVoucherById(String id) async {
    final r = await (_db.select(_db.vouchers)
          ..where((t) => t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
        .getSingleOrNull();

    if (r == null) {
      throw Exception('Voucher not found: $id');
    }

    return VoucherModel.fromMap({
      'id': r.id,
      'companyId': r.companyId,
      'voucherNumber': r.voucherNumber,
      'type': r.type,
      'date': r.date.toIso8601String(),
      'dueDate': r.dueDate?.toIso8601String(),
      'partyId': r.partyId,
      'partyName': r.partyName,
      'status': r.status,
      'paymentMode': r.paymentMode,
      'subtotalInCents': r.subtotalInCents,
      'taxInCents': r.taxInCents,
      'discountInCents': r.discountInCents,
      'totalAmountInCents': r.totalAmountInCents,
      'narration': r.narration,
      'referenceNumber': r.referenceNumber,
      'sourceVoucherId': r.sourceVoucherId,
      'receiptPhotoUrl': r.receiptPhotoUrl,
      'itemsJson': r.itemsJson,
      'createdAt': r.createdAt.toIso8601String(),
      'updatedAt': r.updatedAt.toIso8601String(),
    });
  }

  Future<VoucherModel> createVoucher(VoucherModel voucher) async {
    // Check RBAC permission based on voucher type
    if (voucher.type == VoucherType.sales || voucher.type == VoucherType.salesOrder || voucher.type == VoucherType.estimate) {
      AccessControlService.verifyPermission(_currentRole, UserAction.createCustomerEntry);
    } else if (voucher.type == VoucherType.purchase || voucher.type == VoucherType.purchaseOrder) {
      AccessControlService.verifyPermission(_currentRole, UserAction.createSupplierEntry);
    } else {
      AccessControlService.verifyPermission(_currentRole, UserAction.createCustomerEntry);
    }

    return await _postingEngine.postVoucher(
      voucher: voucher.copyWith(companyId: _currentCompanyId),
      userId: _currentUserId,
    );
  }

  /// Converts an existing Sales Order or Estimate into a posted Sales Invoice (FR-VCH-05).
  Future<VoucherModel> convertToInvoice(String orderOrEstimateId) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.createCustomerEntry);

    final source = await getVoucherById(orderOrEstimateId);
    if (source.status == VoucherStatus.converted) {
      throw Exception('This document has already been converted to an invoice.');
    }

    final now = DateTime.now();
    final invoiceNumber = 'INV-${now.millisecondsSinceEpoch.toString().substring(7)}';

    final invoice = VoucherModel(
      id: 'inv_${now.millisecondsSinceEpoch}',
      companyId: _currentCompanyId,
      voucherNumber: invoiceNumber,
      type: VoucherType.sales,
      date: now,
      dueDate: now.add(const Duration(days: 15)),
      partyId: source.partyId,
      partyName: source.partyName,
      status: VoucherStatus.posted,
      paymentMode: source.paymentMode,
      items: source.items,
      subtotalInCents: source.subtotalInCents,
      taxInCents: source.taxInCents,
      discountInCents: source.discountInCents,
      totalAmountInCents: source.totalAmountInCents,
      narration: 'Converted from ${source.type.displayName} #${source.voucherNumber}',
      referenceNumber: source.voucherNumber,
      sourceVoucherId: source.id,
      createdAt: now,
      updatedAt: now,
    );

    return await _postingEngine.postVoucher(
      voucher: invoice,
      userId: _currentUserId,
    );
  }

  Future<void> voidVoucher(String voucherId) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.voidEntry);

    final voucher = await getVoucherById(voucherId);
    if (voucher.status == VoucherStatus.voided) return;

    await (_db.update(_db.vouchers)..where((t) => t.id.equals(voucherId))).write(
      const VouchersCompanion(
        status: Value('voided'),
      ),
    );

    // If financial entry existed, mark entry voided
    final entryId = 'vch_entry_$voucherId';
    await (_db.update(_db.ledgerEntries)..where((t) => t.id.equals(entryId))).write(
      const LedgerEntriesCompanion(
        isVoided: Value(true),
      ),
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'voucher',
      entityId: voucherId,
      action: AuditAction.voided,
      oldState: voucher.toMap(),
      newState: {'id': voucherId, 'status': 'voided'},
    );
  }
}
