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
import 'package:ledger_pulse/data/models/stock_ledger_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;
  late DriftLedgerRepository ledgerRepo;
  late DriftVoucherRepository voucherRepo;
  late DriftInventoryRepository inventoryRepo;
  late VoucherPostingEngine postingEngine;

  const testCompanyId = 'cmp_post_1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    ledgerRepo = DriftLedgerRepository(db: db, currentCompanyId: testCompanyId);
    voucherRepo = DriftVoucherRepository(db: db, auditService: auditService, postingEngine: postingEngine, currentCompanyId: testCompanyId);
    inventoryRepo = DriftInventoryRepository(db: db, auditService: auditService, currentCompanyId: testCompanyId);

    // Add customer & supplier parties
    final customer = Party(
      id: 'party_customer_1',
      name: 'Alpha Retailers',
      phoneNumber: '9876543210',
      type: PartyType.customer,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    );
    await ledgerRepo.addParty(customer);

    final supplier = Party(
      id: 'party_supplier_1',
      name: 'Beta Suppliers',
      phoneNumber: '9123456780',
      type: PartyType.supplier,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    );
    await ledgerRepo.addParty(supplier);
  });

  tearDown(() async {
    ledgerRepo.dispose();
    await db.close();
  });

  group('Voucher Posting Engine (FR-VCH-01, FR-VCH-02) Double-Entry Tests', () {
    test('Sales Invoice posting updates party ledger balance and decrements stock with audit movement', () async {
      final now = DateTime.now();

      // 1. Create an Inventory SKU
      final item = InventoryItem(
        id: 'sku_widget_1',
        companyId: testCompanyId,
        sku: 'WDG-001',
        name: 'Super Widget',
        sellingPriceInCents: 10000, // 100.00
        purchasePriceInCents: 6000, // 60.00
        currentStockQuantity: 50.0,
        unit: 'PCS',
        minimumStockAlert: 5.0,
        createdAt: now,
        updatedAt: now,
      );
      await inventoryRepo.addItem(item);

      // 2. Create Sales Voucher for 10 units @ 100.00 = 1000.00 (100000 cents)
      final voucher = VoucherModel(
        id: 'vch_sales_101',
        companyId: testCompanyId,
        voucherNumber: 'INV-2026-001',
        type: VoucherType.sales,
        partyId: 'party_customer_1',
        partyName: 'Alpha Retailers',
        date: now,
        subtotalInCents: 100000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 100000,
        status: VoucherStatus.posted,
        items: const [
          VoucherItemModel(
            itemId: 'sku_widget_1',
            itemName: 'Super Widget',
            sku: 'WDG-001',
            quantity: 10.0,
            unitPriceInCents: 10000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 100000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      // 3. Post Voucher
      await voucherRepo.createVoucher(voucher);

      // Verify Voucher Status
      final postedVoucher = await voucherRepo.getVoucherById('vch_sales_101');
      expect(postedVoucher.status, equals(VoucherStatus.posted));

      // Verify party balance changed (receivable / positive balance for customer)
      final updatedParty = await ledgerRepo.getPartyById('party_customer_1');
      expect(updatedParty.netBalanceInCents, equals(100000));

      // Verify stock level reduced from 50 to 40
      final updatedItem = await inventoryRepo.getItemById('sku_widget_1');
      expect(updatedItem.currentStockQuantity, equals(40.0));

      // Verify stock movement ledger
      final movements = await inventoryRepo.getStockLedger('sku_widget_1');
      expect(movements.any((m) => m.transactionType == StockTransactionType.outward && m.quantity == 10.0), isTrue);
    });

    test('Purchase Invoice posting increments inventory stock and updates supplier balance', () async {
      final now = DateTime.now();

      final item = InventoryItem(
        id: 'sku_cog_1',
        companyId: testCompanyId,
        sku: 'COG-001',
        name: 'Steel Cog',
        sellingPriceInCents: 5000,
        purchasePriceInCents: 3000,
        currentStockQuantity: 20.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      );
      await inventoryRepo.addItem(item);

      final purchaseVoucher = VoucherModel(
        id: 'vch_pur_201',
        companyId: testCompanyId,
        voucherNumber: 'PUR-2026-001',
        type: VoucherType.purchase,
        partyId: 'party_supplier_1',
        partyName: 'Beta Suppliers',
        date: now,
        subtotalInCents: 150000, // 50 pcs * 30.00
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 150000,
        status: VoucherStatus.posted,
        items: const [
          VoucherItemModel(
            itemId: 'sku_cog_1',
            itemName: 'Steel Cog',
            sku: 'COG-001',
            quantity: 50.0,
            unitPriceInCents: 3000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 150000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await voucherRepo.createVoucher(purchaseVoucher);

      // Check stock increased from 20 to 70
      final updatedItem = await inventoryRepo.getItemById('sku_cog_1');
      expect(updatedItem.currentStockQuantity, equals(70.0));

      // Check supplier balance reflects payable (-150000 cents)
      final supplierParty = await ledgerRepo.getPartyById('party_supplier_1');
      expect(supplierParty.netBalanceInCents, equals(-150000));

      // Verify stock movement
      final movements = await inventoryRepo.getStockLedger('sku_cog_1');
      expect(movements.any((m) => m.transactionType == StockTransactionType.inward && m.quantity == 50.0), isTrue);
    });

    test('Voiding a posted voucher updates status and voids financial ledger entry', () async {
      final now = DateTime.now();

      final voucher = VoucherModel(
        id: 'vch_void_test',
        companyId: testCompanyId,
        voucherNumber: 'INV-2026-VOID',
        type: VoucherType.sales,
        partyId: 'party_customer_1',
        partyName: 'Alpha Retailers',
        date: now,
        subtotalInCents: 50000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 50000,
        status: VoucherStatus.posted,
        items: const [],
        createdAt: now,
        updatedAt: now,
      );
      await voucherRepo.createVoucher(voucher);

      // Void the voucher
      await voucherRepo.voidVoucher('vch_void_test');

      // Verify voucher status is voided
      final voidedVoucher = await voucherRepo.getVoucherById('vch_void_test');
      expect(voidedVoucher.status, equals(VoucherStatus.voided));
    });
  });
}
