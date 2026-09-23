import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/audit_log_model.dart';
import '../models/stock_ledger_model.dart';
import '../models/transaction_model.dart';
import '../models/voucher_model.dart';

class VoucherPostingEngine {
  final AppDatabase _db;
  final AuditService _auditService;

  VoucherPostingEngine(this._db, this._auditService);

  /// Posts a voucher into the database, generating corresponding double-entry ledger records
  /// and stock ledger movements atomically in a single transaction.
  Future<VoucherModel> postVoucher({
    required VoucherModel voucher,
    required String userId,
  }) async {
    return await _db.transaction(() async {
      final now = DateTime.now();

      // 1. Insert or update the voucher record
      final itemsJsonString = jsonEncode(voucher.items.map((i) => i.toMap()).toList());
      await _db.into(_db.vouchers).insertOnConflictUpdate(
            VouchersCompanion.insert(
              id: voucher.id,
              companyId: Value(voucher.companyId),
              voucherNumber: voucher.voucherNumber,
              type: voucher.type.name,
              date: voucher.date,
              dueDate: Value(voucher.dueDate),
              partyId: Value(voucher.partyId),
              partyName: Value(voucher.partyName),
              status: Value(voucher.status.name),
              paymentMode: Value(voucher.paymentMode.name),
              subtotalInCents: Value(voucher.subtotalInCents),
              taxInCents: Value(voucher.taxInCents),
              discountInCents: Value(voucher.discountInCents),
              totalAmountInCents: Value(voucher.totalAmountInCents),
              narration: Value(voucher.narration),
              referenceNumber: Value(voucher.referenceNumber),
              sourceVoucherId: Value(voucher.sourceVoucherId),
              receiptPhotoUrl: Value(voucher.receiptPhotoUrl),
              itemsJson: Value(itemsJsonString),
              createdAt: Value(voucher.createdAt),
              updatedAt: Value(now),
            ),
          );

      // 2. Double-Entry Posting for Financial Vouchers
      if (voucher.type.isFinancialPosting && voucher.status == VoucherStatus.posted) {
        await _postDoubleEntryLedger(voucher);
        await _postInventoryStockMovements(voucher);
      }

      // 3. If this voucher converted a source order or estimate, mark source as converted
      if (voucher.sourceVoucherId != null) {
        await (_db.update(_db.vouchers)..where((t) => t.id.equals(voucher.sourceVoucherId!))).write(
          const VouchersCompanion(
            status: Value('converted'),
          ),
        );
      }

      // 4. Audit Log
      await _auditService.recordLog(
        companyId: voucher.companyId,
        userId: userId,
        entityType: 'voucher',
        entityId: voucher.id,
        action: AuditAction.insert,
        newState: voucher.toMap(),
      );

      // 5. Sync Outbox
      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: const Uuid().v4(),
              targetTable: 'vouchers',
              recordId: voucher.id,
              mutationType: 'INSERT',
              payload: jsonEncode({
                ...voucher.toMap(),
                'companyId': voucher.companyId,
              }),
            ),
          );

      return voucher;
    });
  }

  Future<void> _postDoubleEntryLedger(VoucherModel voucher) async {
    if (voucher.partyId == null || voucher.totalAmountInCents == 0) return;

    final entryId = 'vch_entry_${voucher.id}';
    EntryType entryType;
    String note = voucher.narration ?? '${voucher.type.displayName} #${voucher.voucherNumber}';

    switch (voucher.type) {
      case VoucherType.sales:
        // Sales to customer -> You will get (Receivable) -> EntryType.gave
        entryType = EntryType.gave;
        break;
      case VoucherType.purchase:
        // Purchase from supplier -> You owe (Payable) -> EntryType.got
        entryType = EntryType.got;
        break;
      case VoucherType.receipt:
        // Payment received from party -> Reduces receivable -> EntryType.got
        entryType = EntryType.got;
        break;
      case VoucherType.payment:
        // Payment made to party -> Reduces payable -> EntryType.gave
        entryType = EntryType.gave;
        break;
      case VoucherType.contra:
      case VoucherType.journal:
        entryType = EntryType.gave;
        break;
      default:
        return;
    }

    await _db.into(_db.ledgerEntries).insertOnConflictUpdate(
          LedgerEntriesCompanion.insert(
            id: entryId,
            companyId: Value(voucher.companyId),
            partyId: voucher.partyId!,
            amountInCents: voucher.totalAmountInCents,
            type: entryType,
            date: voucher.date,
            note: Value(note),
            receiptPhotoUrl: Value(voucher.receiptPhotoUrl),
            isVoided: const Value(false),
            createdAt: Value(voucher.date),
          ),
        );

    // Recalculate party balance
    await _recalculatePartyBalance(voucher.partyId!, voucher.companyId);
  }

  Future<void> _postInventoryStockMovements(VoucherModel voucher) async {
    if (voucher.items.isEmpty) return;

    for (int i = 0; i < voucher.items.length; i++) {
      final item = voucher.items[i];
      final stockEntryId = 'stk_${voucher.id}_$i';

      StockTransactionType txnType;
      double stockDelta;

      if (voucher.type == VoucherType.sales) {
        // Sale reduces stock
        txnType = StockTransactionType.outward;
        stockDelta = -item.quantity;
      } else if (voucher.type == VoucherType.purchase) {
        // Purchase adds stock
        txnType = StockTransactionType.inward;
        stockDelta = item.quantity;
      } else {
        continue;
      }

      // Query current item
      final currentItem = await (_db.select(_db.inventoryItems)
            ..where((t) => t.id.equals(item.itemId) & t.companyId.equals(voucher.companyId)))
          .getSingleOrNull();

      if (currentItem != null) {
        final newStockQty = currentItem.currentStockQuantity + stockDelta;

        // Update item running stock
        await (_db.update(_db.inventoryItems)..where((t) => t.id.equals(item.itemId))).write(
          InventoryItemsCompanion(
            currentStockQuantity: Value(newStockQty),
            updatedAt: Value(DateTime.now()),
          ),
        );

        // Record stock ledger movement
        await _db.into(_db.stockLedger).insertOnConflictUpdate(
              StockLedgerCompanion.insert(
                id: stockEntryId,
                companyId: Value(voucher.companyId),
                itemId: item.itemId,
                voucherId: Value(voucher.id),
                transactionType: txnType.name,
                quantity: item.quantity,
                unitCostInCents: Value(item.unitPriceInCents),
                totalCostInCents: Value(item.totalInCents),
                runningStockQuantity: Value(newStockQty),
                date: voucher.date,
                note: Value('${voucher.type.displayName} #${voucher.voucherNumber}'),
                createdAt: Value(DateTime.now()),
              ),
            );
      }
    }
  }

  Future<void> _recalculatePartyBalance(String partyId, String companyId) async {
    final partyQuery = _db.select(_db.parties)
      ..where((t) => t.id.equals(partyId) & t.companyId.equals(companyId));
    final party = await partyQuery.getSingleOrNull();
    if (party == null) return;

    final entriesQuery = _db.select(_db.ledgerEntries)
      ..where((t) => t.partyId.equals(partyId) & t.companyId.equals(companyId));
    final entries = await entriesQuery.get();

    int newBalance = 0;
    DateTime latestDate = party.lastUpdated;

    for (final entry in entries) {
      if (entry.type == EntryType.gave) {
        newBalance += entry.amountInCents;
      } else {
        newBalance -= entry.amountInCents;
      }
      if (entry.date.isAfter(latestDate)) {
        latestDate = entry.date;
      }
    }

    await (_db.update(_db.parties)..where((t) => t.id.equals(partyId) & t.companyId.equals(companyId))).write(
      PartiesCompanion(
        netBalanceInCents: Value(newBalance),
        lastUpdated: Value(latestDate),
      ),
    );
  }
}
