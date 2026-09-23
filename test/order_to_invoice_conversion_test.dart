import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_inventory_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;
  late DriftLedgerRepository ledgerRepo;
  late DriftVoucherRepository voucherRepo;
  late DriftInventoryRepository inventoryRepo;
  late VoucherPostingEngine postingEngine;

  const testCompanyId = 'cmp_order_1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    ledgerRepo = DriftLedgerRepository(db: db, currentCompanyId: testCompanyId);
    voucherRepo = DriftVoucherRepository(db: db, auditService: auditService, postingEngine: postingEngine, currentCompanyId: testCompanyId);
    inventoryRepo = DriftInventoryRepository(db: db, auditService: auditService, currentCompanyId: testCompanyId);

    final party = Party(
      id: 'party_client_1',
      name: 'Delta Enterprises',
      phoneNumber: '9988776655',
      type: PartyType.customer,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    );
    await ledgerRepo.addParty(party);
  });

  tearDown(() async {
    ledgerRepo.dispose();
    await db.close();
  });

  group('Order to Invoice Workflow (FR-VCH-05) Tests', () {
    test('Converting a Sales Order generates a Sales Invoice preserving line items and updating inventory & receivable', () async {
      final now = DateTime.now();

      // 1. Create SKU
      final item = InventoryItem(
        id: 'sku_chair_1',
        companyId: testCompanyId,
        sku: 'CHAIR-01',
        name: 'Ergonomic Office Chair',
        sellingPriceInCents: 25000,
        purchasePriceInCents: 15000,
        currentStockQuantity: 30.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      );
      await inventoryRepo.addItem(item);

      // 2. Create Sales Order (non-accounting document)
      final salesOrder = VoucherModel(
        id: 'order_so_1001',
        companyId: testCompanyId,
        voucherNumber: 'SO-2026-0001',
        type: VoucherType.salesOrder,
        partyId: 'party_client_1',
        partyName: 'Delta Enterprises',
        date: now,
        subtotalInCents: 125000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 125000,
        status: VoucherStatus.posted,
        items: const [
          VoucherItemModel(
            itemId: 'sku_chair_1',
            itemName: 'Ergonomic Office Chair',
            sku: 'CHAIR-01',
            quantity: 5.0,
            unitPriceInCents: 25000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 125000,
          ),
        ],
        narration: 'Delivery requested by end of week',
        createdAt: now,
        updatedAt: now,
      );
      await voucherRepo.createVoucher(salesOrder);

      // Verify stock and party balance are unchanged (Sales Orders do not post accounting entries)
      final initialStock = await inventoryRepo.getItemById('sku_chair_1');
      expect(initialStock.currentStockQuantity, equals(30.0));
      final initialParty = await ledgerRepo.getPartyById('party_client_1');
      expect(initialParty.netBalanceInCents, equals(0));

      // 3. Convert Order to Sales Invoice
      final invoice = await voucherRepo.convertToInvoice('order_so_1001');

      // Verify generated invoice
      expect(invoice.type, equals(VoucherType.sales));
      expect(invoice.sourceVoucherId, equals('order_so_1001'));
      expect(invoice.partyId, equals('party_client_1'));
      expect(invoice.totalAmountInCents, equals(125000));
      expect(invoice.items.length, equals(1));
      expect(invoice.items.first.itemId, equals('sku_chair_1'));
      expect(invoice.items.first.quantity, equals(5.0));

      // Verify original order is marked as converted
      final updatedOrder = await voucherRepo.getVoucherById('order_so_1001');
      expect(updatedOrder.status, equals(VoucherStatus.converted));

      // Verify stock decreased from 30 to 25
      final finalStock = await inventoryRepo.getItemById('sku_chair_1');
      expect(finalStock.currentStockQuantity, equals(25.0));

      // Verify party balance is updated to 125000 cents
      final finalParty = await ledgerRepo.getPartyById('party_client_1');
      expect(finalParty.netBalanceInCents, equals(125000));
    });

    test('Converting an Estimate to Sales Invoice workflow', () async {
      final now = DateTime.now();

      final estimate = VoucherModel(
        id: 'est_2001',
        companyId: testCompanyId,
        voucherNumber: 'EST-2026-0001',
        type: VoucherType.estimate,
        partyId: 'party_client_1',
        partyName: 'Delta Enterprises',
        date: now,
        subtotalInCents: 40000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 40000,
        status: VoucherStatus.posted,
        items: const [
          VoucherItemModel(
            itemId: 'custom_service_1',
            itemName: 'Consulting Service',
            sku: 'SRV-01',
            quantity: 4.0,
            unitPriceInCents: 10000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 40000,
          ),
        ],
        narration: 'Quote valid for 15 days',
        createdAt: now,
        updatedAt: now,
      );
      await voucherRepo.createVoucher(estimate);

      final invoice = await voucherRepo.convertToInvoice('est_2001');

      expect(invoice.type, equals(VoucherType.sales));
      expect(invoice.sourceVoucherId, equals('est_2001'));
      expect(invoice.totalAmountInCents, equals(40000));
    });
  });
}
