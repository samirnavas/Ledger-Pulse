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

  const testCompanyId = 'cmp_workflow_test';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    ledgerRepo = DriftLedgerRepository(
      db: db,
      postingEngine: postingEngine,
      currentCompanyId: testCompanyId,
    );
    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: testCompanyId,
    );
    inventoryRepo = DriftInventoryRepository(
      db: db,
      auditService: auditService,
      currentCompanyId: testCompanyId,
    );

    // Setup Test Customer and Test Supplier
    await ledgerRepo.addParty(Party(
      id: 'party_cust_1',
      name: 'Acme Retailers',
      phoneNumber: '9876543210',
      type: PartyType.customer,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    ));

    await ledgerRepo.addParty(Party(
      id: 'party_supp_1',
      name: 'Global Wholesale Supply',
      phoneNumber: '9123456780',
      type: PartyType.supplier,
      netBalanceInCents: 0,
      lastUpdated: DateTime.now(),
    ));

    await postingEngine.ensureCompanyAccounts(testCompanyId);
  });

  tearDown(() async {
    ledgerRepo.dispose();
    await db.close();
  });

  group('Document Workflow & Type Behavior Tests', () {
    test('1. Document Number Generation is sequential and type-specific', () async {
      final invNum1 = await voucherRepo.generateNextVoucherNumber(VoucherType.sales);
      expect(invNum1, equals('INV-0001'));

      final soNum1 = await voucherRepo.generateNextVoucherNumber(VoucherType.salesOrder);
      expect(soNum1, equals('SO-0001'));

      final estNum1 = await voucherRepo.generateNextVoucherNumber(VoucherType.estimate);
      expect(estNum1, equals('EST-0001'));

      final purNum1 = await voucherRepo.generateNextVoucherNumber(VoucherType.purchase);
      expect(purNum1, equals('PUR-0001'));

      // Create an invoice with INV-0001
      final now = DateTime.now();
      await voucherRepo.createVoucher(VoucherModel(
        id: 'vch_inv_1',
        companyId: testCompanyId,
        voucherNumber: invNum1,
        type: VoucherType.sales,
        partyId: 'party_cust_1',
        partyName: 'Acme Retailers',
        date: now,
        subtotalInCents: 10000,
        taxInCents: 1800,
        discountInCents: 0,
        totalAmountInCents: 11800,
        status: VoucherStatus.posted,
        createdAt: now,
        updatedAt: now,
      ));

      // Next invoice number should now be INV-0002, while SO remains SO-0001
      final invNum2 = await voucherRepo.generateNextVoucherNumber(VoucherType.sales);
      expect(invNum2, equals('INV-0002'));

      final soNumCheck = await voucherRepo.generateNextVoucherNumber(VoucherType.salesOrder);
      expect(soNumCheck, equals('SO-0001'));
    });

    test('2. Sales Invoice: posted updates accounting, customer receivable, Output GST, and stock for goods only', () async {
      final now = DateTime.now();

      // Create 1 inventory item (Goods) and 1 non-stock Service
      await inventoryRepo.addItem(InventoryItem(
        id: 'sku_prod_laptop',
        companyId: testCompanyId,
        sku: 'LAP-001',
        name: 'Ultra Laptop',
        sellingPriceInCents: 80000,
        purchasePriceInCents: 60000,
        currentStockQuantity: 10.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      ));

      // Create posted Sales Invoice with 1 Goods item and 1 Service item
      final invoice = VoucherModel(
        id: 'vch_inv_real_sale',
        companyId: testCompanyId,
        voucherNumber: 'INV-0001',
        type: VoucherType.sales,
        partyId: 'party_cust_1',
        partyName: 'Acme Retailers',
        date: now,
        subtotalInCents: 100000, // 80000 (laptop) + 20000 (service)
        taxInCents: 18000,       // 18% GST = 18000
        discountInCents: 0,
        totalAmountInCents: 118000,
        status: VoucherStatus.posted,
        paymentMode: PaymentMode.credit,
        items: const [
          VoucherItemModel(
            itemId: 'sku_prod_laptop',
            itemName: 'Ultra Laptop',
            sku: 'LAP-001',
            quantity: 1.0,
            unitPriceInCents: 80000,
            taxRatePercent: 18,
            discountInCents: 0,
            totalInCents: 80000,
          ),
          VoucherItemModel(
            itemId: 'srv_installation_fee',
            itemName: 'On-site Setup Service',
            sku: 'SRV-SETUP',
            quantity: 1.0,
            unitPriceInCents: 20000,
            taxRatePercent: 18,
            discountInCents: 0,
            totalInCents: 20000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(invoice);

      // Verify Customer Receivable updated to 118000
      final custParty = await ledgerRepo.getPartyById('party_cust_1');
      expect(custParty.netBalanceInCents, equals(118000));

      // Verify Inventory: Laptop reduced from 10 to 9
      final updatedLaptop = await inventoryRepo.getItemById('sku_prod_laptop');
      expect(updatedLaptop.currentStockQuantity, equals(9.0));

      // Verify Double-Entry Accounting Journal entries
      final journals = await ledgerRepo.getJournals();
      final invoiceJournals = journals.where((j) => j.voucherId == 'vch_inv_real_sale').toList();
      expect(invoiceJournals.length, equals(1));
      final journal = invoiceJournals.first;
      expect(journal.isBalanced, isTrue);
      expect(journal.lines.length, equals(3)); // AR (Debit 118000), Sales Revenue (Credit 100000), GST Output (Credit 18000)

      final totalDebits = journal.lines.fold<int>(0, (sum, e) => sum + e.debitInCents);
      final totalCredits = journal.lines.fold<int>(0, (sum, e) => sum + e.creditInCents);
      expect(totalDebits, equals(118000));
      expect(totalCredits, equals(118000));
    });

    test('3. Draft Sales Invoice does NOT affect accounting, party balance, or stock', () async {
      final now = DateTime.now();

      await inventoryRepo.addItem(InventoryItem(
        id: 'sku_monitor',
        companyId: testCompanyId,
        sku: 'MON-01',
        name: '4K Monitor',
        sellingPriceInCents: 40000,
        purchasePriceInCents: 30000,
        currentStockQuantity: 15.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      ));

      final draftInvoice = VoucherModel(
        id: 'vch_draft_inv',
        companyId: testCompanyId,
        voucherNumber: 'INV-0001',
        type: VoucherType.sales,
        partyId: 'party_cust_1',
        partyName: 'Acme Retailers',
        date: now,
        subtotalInCents: 40000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 40000,
        status: VoucherStatus.draft,
        items: const [
          VoucherItemModel(
            itemId: 'sku_monitor',
            itemName: '4K Monitor',
            sku: 'MON-01',
            quantity: 2.0,
            unitPriceInCents: 40000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 40000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(draftInvoice);

      // Verify Stock unchanged (still 15.0)
      final stockItem = await inventoryRepo.getItemById('sku_monitor');
      expect(stockItem.currentStockQuantity, equals(15.0));

      // Verify Party balance unchanged (still 0)
      final party = await ledgerRepo.getPartyById('party_cust_1');
      expect(party.netBalanceInCents, equals(0));

      // Verify no Journal entries
      final journals = await ledgerRepo.getJournals();
      final draftJournals = journals.where((j) => j.voucherId == 'vch_draft_inv').toList();
      expect(draftJournals.isEmpty, isTrue);
    });

    test('4. Sales Order: does NOT affect accounting or stock, and can be converted to Sales Invoice', () async {
      final now = DateTime.now();

      await inventoryRepo.addItem(InventoryItem(
        id: 'sku_desk',
        companyId: testCompanyId,
        sku: 'DSK-01',
        name: 'Standing Desk',
        sellingPriceInCents: 50000,
        purchasePriceInCents: 35000,
        currentStockQuantity: 20.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      ));

      final salesOrder = VoucherModel(
        id: 'vch_so_100',
        companyId: testCompanyId,
        voucherNumber: 'SO-0001',
        type: VoucherType.salesOrder,
        partyId: 'party_cust_1',
        partyName: 'Acme Retailers',
        date: now,
        subtotalInCents: 100000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 100000,
        status: VoucherStatus.confirmed,
        items: const [
          VoucherItemModel(
            itemId: 'sku_desk',
            itemName: 'Standing Desk',
            sku: 'DSK-01',
            quantity: 2.0,
            unitPriceInCents: 50000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 100000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(salesOrder);

      // Verify no stock or ledger impact
      final initialStock = await inventoryRepo.getItemById('sku_desk');
      expect(initialStock.currentStockQuantity, equals(20.0));
      final initialParty = await ledgerRepo.getPartyById('party_cust_1');
      expect(initialParty.netBalanceInCents, equals(0));

      // Convert Sales Order to Sales Invoice
      final generatedInvoice = await voucherRepo.convertSalesOrderToSalesInvoice('vch_so_100');

      expect(generatedInvoice.type, equals(VoucherType.sales));
      expect(generatedInvoice.sourceVoucherId, equals('vch_so_100'));
      expect(generatedInvoice.referenceNumber, equals('SO-0001'));
      expect(generatedInvoice.items.length, equals(1));
      expect(generatedInvoice.items.first.quantity, equals(2.0));

      // Check source SO status updated to 'converted'
      final updatedSo = await voucherRepo.getVoucherById('vch_so_100');
      expect(updatedSo.status, equals(VoucherStatus.converted));

      // Check stock decremented by 2 (20 -> 18)
      final afterStock = await inventoryRepo.getItemById('sku_desk');
      expect(afterStock.currentStockQuantity, equals(18.0));

      // Check Customer receivable updated to 100000
      final afterParty = await ledgerRepo.getPartyById('party_cust_1');
      expect(afterParty.netBalanceInCents, equals(100000));

      // Check duplicate conversion attempt throws Exception
      expect(
        () async => await voucherRepo.convertSalesOrderToSalesInvoice('vch_so_100'),
        throwsA(isA<Exception>()),
      );
    });

    test('5. Estimate / Quote: does NOT affect accounting/stock, converts to Sales Order or Sales Invoice', () async {
      final now = DateTime.now();

      await inventoryRepo.addItem(InventoryItem(
        id: 'sku_tablet',
        companyId: testCompanyId,
        sku: 'TAB-01',
        name: 'Graphic Tablet',
        sellingPriceInCents: 30000,
        purchasePriceInCents: 20000,
        currentStockQuantity: 12.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      ));

      // Estimate 1: Convert to Sales Order
      final estimate1 = VoucherModel(
        id: 'vch_est_1',
        companyId: testCompanyId,
        voucherNumber: 'EST-0001',
        type: VoucherType.estimate,
        partyId: 'party_cust_1',
        partyName: 'Acme Retailers',
        date: now,
        subtotalInCents: 60000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 60000,
        status: VoucherStatus.accepted,
        items: const [
          VoucherItemModel(
            itemId: 'sku_tablet',
            itemName: 'Graphic Tablet',
            sku: 'TAB-01',
            quantity: 2.0,
            unitPriceInCents: 30000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 60000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(estimate1);

      // Convert Estimate 1 to Sales Order
      final so = await voucherRepo.convertEstimateToSalesOrder('vch_est_1');
      expect(so.type, equals(VoucherType.salesOrder));
      expect(so.sourceVoucherId, equals('vch_est_1'));
      expect(so.referenceNumber, equals('EST-0001'));
      expect(so.status, equals(VoucherStatus.confirmed));

      // Verify stock & accounting remain unchanged after creating SO
      final stockAfterSo = await inventoryRepo.getItemById('sku_tablet');
      expect(stockAfterSo.currentStockQuantity, equals(12.0));
      final partyAfterSo = await ledgerRepo.getPartyById('party_cust_1');
      expect(partyAfterSo.netBalanceInCents, equals(0));

      // Estimate 2: Convert directly to Sales Invoice
      final estimate2 = VoucherModel(
        id: 'vch_est_2',
        companyId: testCompanyId,
        voucherNumber: 'EST-0002',
        type: VoucherType.estimate,
        partyId: 'party_cust_1',
        partyName: 'Acme Retailers',
        date: now,
        subtotalInCents: 30000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 30000,
        status: VoucherStatus.sent,
        items: const [
          VoucherItemModel(
            itemId: 'sku_tablet',
            itemName: 'Graphic Tablet',
            sku: 'TAB-01',
            quantity: 1.0,
            unitPriceInCents: 30000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 30000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(estimate2);

      final inv = await voucherRepo.convertEstimateToSalesInvoice('vch_est_2');
      expect(inv.type, equals(VoucherType.sales));
      expect(inv.sourceVoucherId, equals('vch_est_2'));
      expect(inv.referenceNumber, equals('EST-0002'));

      // Stock should now decrease by 1 (12 -> 11)
      final stockAfterInv = await inventoryRepo.getItemById('sku_tablet');
      expect(stockAfterInv.currentStockQuantity, equals(11.0));

      // Customer balance should now be 30000
      final partyAfterInv = await ledgerRepo.getPartyById('party_cust_1');
      expect(partyAfterInv.netBalanceInCents, equals(30000));

      // Duplicate conversion of already converted estimate should throw Exception
      expect(
        () async => await voucherRepo.convertEstimateToSalesInvoice('vch_est_2'),
        throwsA(isA<Exception>()),
      );
      expect(
        () async => await voucherRepo.convertEstimateToSalesOrder('vch_est_1'),
        throwsA(isA<Exception>()),
      );
    });

    test('6. Purchase: posted increases inventory stock, records Input GST (ITC), and updates Supplier payable', () async {
      final now = DateTime.now();

      await inventoryRepo.addItem(InventoryItem(
        id: 'sku_raw_wood',
        companyId: testCompanyId,
        sku: 'RAW-WD-01',
        name: 'Timber Wood Plank',
        sellingPriceInCents: 1500,
        purchasePriceInCents: 1000,
        currentStockQuantity: 50.0,
        unit: 'PCS',
        createdAt: now,
        updatedAt: now,
      ));

      final purchase = VoucherModel(
        id: 'vch_pur_100',
        companyId: testCompanyId,
        voucherNumber: 'PUR-0001',
        type: VoucherType.purchase,
        partyId: 'party_supp_1',
        partyName: 'Global Wholesale Supply',
        date: now,
        subtotalInCents: 50000, // 50 planks * 1000
        taxInCents: 9000,       // 18% Input GST
        discountInCents: 0,
        totalAmountInCents: 59000,
        status: VoucherStatus.posted,
        paymentMode: PaymentMode.credit,
        items: const [
          VoucherItemModel(
            itemId: 'sku_raw_wood',
            itemName: 'Timber Wood Plank',
            sku: 'RAW-WD-01',
            quantity: 50.0,
            unitPriceInCents: 1000,
            taxRatePercent: 18,
            discountInCents: 0,
            totalInCents: 50000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(purchase);

      // Verify Stock increased from 50 to 100
      final updatedWood = await inventoryRepo.getItemById('sku_raw_wood');
      expect(updatedWood.currentStockQuantity, equals(100.0));

      // Verify Supplier Payable is credited (-59000)
      final supplierParty = await ledgerRepo.getPartyById('party_supp_1');
      expect(supplierParty.netBalanceInCents, equals(-59000));

      // Verify Double Entry Journal entries
      final journals = await ledgerRepo.getJournals();
      final purchaseJournals = journals.where((j) => j.voucherId == 'vch_pur_100').toList();
      expect(purchaseJournals.length, equals(1));
      final journal = purchaseJournals.first;
      expect(journal.isBalanced, isTrue);
      expect(journal.lines.length, equals(3)); // Purchase Expense (Debit 50000), Input GST (Debit 9000), AP (Credit 59000)

      final totalDebits = journal.lines.fold<int>(0, (sum, e) => sum + e.debitInCents);
      final totalCredits = journal.lines.fold<int>(0, (sum, e) => sum + e.creditInCents);
      expect(totalDebits, equals(59000));
      expect(totalCredits, equals(59000));
    });
  });
}
