import 'package:drift/drift.dart';
import '../accounting/voucher_posting_engine.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/rbac_model.dart';
import '../models/voucher_model.dart';
import '../security/access_control_service.dart';

class DriftVoucherRepository {
  final AppDatabase _db;
  final VoucherPostingEngine _postingEngine;
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

  /// Generates the next sequential unique voucher number for a company and document type.
  /// Format: EST-0001, SO-0001, INV-0001, PUR-0001, etc.
  Future<String> generateNextVoucherNumber(VoucherType type, {String? companyId}) async {
    final targetCompanyId = companyId ?? _currentCompanyId;
    final prefix = type.prefix;

    final existingRows = await (_db.select(_db.vouchers)
          ..where((t) => t.companyId.equals(targetCompanyId) & (t.type.equals(type.name) | t.voucherNumber.like('$prefix-%'))))
        .get();

    int maxSequence = 0;
    final existingNumbers = <String>{};

    for (final row in existingRows) {
      existingNumbers.add(row.voucherNumber.toUpperCase());
      final vNum = row.voucherNumber;
      if (vNum.startsWith('$prefix-')) {
        final suffix = vNum.substring(prefix.length + 1);
        final num = int.tryParse(suffix);
        if (num != null && num > maxSequence) {
          maxSequence = num;
        }
      }
    }

    int nextNum = maxSequence + 1;
    String candidate = '$prefix-${nextNum.toString().padLeft(4, '0')}';

    while (existingNumbers.contains(candidate.toUpperCase())) {
      nextNum++;
      candidate = '$prefix-${nextNum.toString().padLeft(4, '0')}';
    }

    return candidate;
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

  /// Converts an existing Estimate into a confirmed Sales Order.
  Future<VoucherModel> convertEstimateToSalesOrder(String estimateId) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.createCustomerEntry);

    final source = await getVoucherById(estimateId);
    if (source.type != VoucherType.estimate) {
      throw Exception('Source document is not an Estimate/Quotation.');
    }
    if (source.status == VoucherStatus.converted) {
      throw Exception('This Estimate has already been converted.');
    }

    final now = DateTime.now();
    final orderNumber = await generateNextVoucherNumber(VoucherType.salesOrder);

    final salesOrder = VoucherModel(
      id: 'so_${now.millisecondsSinceEpoch}',
      companyId: _currentCompanyId,
      voucherNumber: orderNumber,
      type: VoucherType.salesOrder,
      date: now,
      dueDate: now.add(const Duration(days: 7)),
      partyId: source.partyId,
      partyName: source.partyName,
      status: VoucherStatus.confirmed,
      paymentMode: source.paymentMode,
      items: source.items,
      subtotalInCents: source.subtotalInCents,
      taxInCents: source.taxInCents,
      cgstInCents: source.cgstInCents,
      sgstInCents: source.sgstInCents,
      igstInCents: source.igstInCents,
      discountInCents: source.discountInCents,
      totalAmountInCents: source.totalAmountInCents,
      placeOfSupplyStateCode: source.placeOfSupplyStateCode,
      narration: 'Converted from Estimate #${source.voucherNumber}',
      referenceNumber: source.voucherNumber,
      sourceVoucherId: source.id,
      createdAt: now,
      updatedAt: now,
    );

    return await createVoucher(salesOrder);
  }

  /// Converts an existing Estimate into a posted Sales Invoice.
  Future<VoucherModel> convertEstimateToSalesInvoice(String estimateId) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.createCustomerEntry);

    final source = await getVoucherById(estimateId);
    if (source.type != VoucherType.estimate) {
      throw Exception('Source document is not an Estimate/Quotation.');
    }
    if (source.status == VoucherStatus.converted) {
      throw Exception('This Estimate has already been converted.');
    }

    final now = DateTime.now();
    final invoiceNumber = await generateNextVoucherNumber(VoucherType.sales);

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
      cgstInCents: source.cgstInCents,
      sgstInCents: source.sgstInCents,
      igstInCents: source.igstInCents,
      discountInCents: source.discountInCents,
      totalAmountInCents: source.totalAmountInCents,
      placeOfSupplyStateCode: source.placeOfSupplyStateCode,
      narration: 'Converted from Estimate #${source.voucherNumber}',
      referenceNumber: source.voucherNumber,
      sourceVoucherId: source.id,
      createdAt: now,
      updatedAt: now,
    );

    return await createVoucher(invoice);
  }

  /// Converts an existing Sales Order into a posted Sales Invoice.
  Future<VoucherModel> convertSalesOrderToSalesInvoice(String salesOrderId) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.createCustomerEntry);

    final source = await getVoucherById(salesOrderId);
    if (source.type != VoucherType.salesOrder) {
      throw Exception('Source document is not a Sales Order.');
    }
    if (source.status == VoucherStatus.converted) {
      throw Exception('This Sales Order has already been converted.');
    }

    final now = DateTime.now();
    final invoiceNumber = await generateNextVoucherNumber(VoucherType.sales);

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
      cgstInCents: source.cgstInCents,
      sgstInCents: source.sgstInCents,
      igstInCents: source.igstInCents,
      discountInCents: source.discountInCents,
      totalAmountInCents: source.totalAmountInCents,
      placeOfSupplyStateCode: source.placeOfSupplyStateCode,
      narration: 'Converted from Sales Order #${source.voucherNumber}',
      referenceNumber: source.voucherNumber,
      sourceVoucherId: source.id,
      createdAt: now,
      updatedAt: now,
    );

    return await createVoucher(invoice);
  }

  /// Converts an existing Sales Order or Estimate into a posted Sales Invoice (FR-VCH-05).
  Future<VoucherModel> convertToInvoice(String orderOrEstimateId) async {
    final source = await getVoucherById(orderOrEstimateId);
    if (source.type == VoucherType.estimate) {
      return await convertEstimateToSalesInvoice(orderOrEstimateId);
    } else if (source.type == VoucherType.salesOrder) {
      return await convertSalesOrderToSalesInvoice(orderOrEstimateId);
    } else if (source.type == VoucherType.sales) {
      throw Exception('Document is already a Sales Invoice.');
    } else {
      return await convertSalesOrderToSalesInvoice(orderOrEstimateId);
    }
  }

  Future<void> voidVoucher(String voucherId) async {
    AccessControlService.verifyPermission(_currentRole, UserAction.voidEntry);
    await _postingEngine.voidVoucher(
      voucherId: voucherId,
      companyId: _currentCompanyId,
      userId: _currentUserId,
    );
  }
}
