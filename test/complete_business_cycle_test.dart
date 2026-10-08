import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_inventory_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/stock_ledger_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/reporting/financial_statement_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftLedgerRepository ledgerRepo;
  late DriftVoucherRepository voucherRepo;
  late DriftInventoryRepository inventoryRepo;

  const testCompanyId = 'cmp_business_cycle_1';
  const testUserId = 'usr_test_operator';

  final testCompany = Company(
    id: testCompanyId,
    name: 'Ledger Pulse Demo Corp',
    legalName: 'Ledger Pulse Technologies Pvt Ltd',
    gstin: '29ABCDE1234F1ZH',
    stateCode: '29',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);

    ledgerRepo = DriftLedgerRepository(
      db: db,
      postingEngine: postingEngine,
      currentCompanyId: testCompanyId,
      currentUserId: testUserId,
    );

    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: testCompanyId,
      currentUserId: testUserId,
    );

    inventoryRepo = DriftInventoryRepository(
      db: db,
      auditService: auditService,
      currentCompanyId: testCompanyId,
    );

    // Initialize Chart of Accounts for company
    await postingEngine.ensureCompanyAccounts(testCompanyId);
  });

  tearDown(() async {
    ledgerRepo.dispose();
    await db.close();
  });

  test('Complete Business Cycle: Item Master -> Sales -> Purchase -> Stock -> AR/AP -> Receipts/Payments -> Double-Entry Statements', () async {
    final now = DateTime(2026, 10, 8, 10, 0);

    // ==========================================
    // 1. CREATE ITEM MASTER INVENTORY ITEM
    // Item: "Test Product", Selling Price: ₹1,000 (100000 cents), Cost: ₹600 (60000 cents), GST: 18%, Opening Stock: 10
    // ==========================================
    const testItemId = 'item_test_product_001';
    final productItem = InventoryItem(
      id: testItemId,
      companyId: testCompanyId,
      name: 'Test Product',
      sku: 'SKU-TP-01',
      hsnCode: '8471',
      unit: 'PCS',
      sellingPriceInCents: 100000, // ₹1,000.00
      purchasePriceInCents: 60000, // ₹600.00
      taxRatePercent: 18.0,
      currentStockQuantity: 10.0,
      minimumStockAlert: 2.0,
      createdAt: now,
      updatedAt: now,
    );
    await inventoryRepo.addItem(productItem);

    final initialItem = await inventoryRepo.getItemById(testItemId);
    expect(initialItem.currentStockQuantity, equals(10.0));
    expect(initialItem.sellingPriceInCents, equals(100000));
    expect(initialItem.purchasePriceInCents, equals(60000));
    expect(initialItem.taxRatePercent, equals(18.0));

    // ==========================================
    // 2. CREATE CUSTOMER & SUPPLIER
    // Customer: "Test Customer", Supplier: "Test Supplier"
    // ==========================================
    const customerId = 'party_customer_001';
    final customer = Party(
      id: customerId,
      name: 'Test Customer',
      phoneNumber: '+91 99887 76655',
      type: PartyType.customer,
      gstin: '29AABCT1332L1ZV',
      stateCode: '29',
      netBalanceInCents: 0,
      lastUpdated: now,
    );
    await ledgerRepo.addParty(customer);

    const supplierId = 'party_supplier_001';
    final supplier = Party(
      id: supplierId,
      name: 'Test Supplier',
      phoneNumber: '+91 88776 65544',
      type: PartyType.supplier,
      gstin: '29XYZPA5566K1Z9',
      stateCode: '29',
      netBalanceInCents: 0,
      lastUpdated: now,
    );
    await ledgerRepo.addParty(supplier);

    expect((await ledgerRepo.getPartyById(customerId)).netBalanceInCents, equals(0));
    expect((await ledgerRepo.getPartyById(supplierId)).netBalanceInCents, equals(0));

    // ==========================================
    // 3. POST CREDIT SALES INVOICE
    // Test Product x 1 @ ₹1,000 + 18% GST = Total ₹1,180 (Taxable ₹1,000, CGST ₹90, SGST ₹90)
    // ==========================================
    final salesVoucher = VoucherModel(
      id: 'vch_sales_001',
      companyId: testCompanyId,
      voucherNumber: 'INV-2026-001',
      type: VoucherType.sales,
      status: VoucherStatus.posted,
      date: now,
      partyId: customerId,
      partyName: customer.name,
      paymentMode: PaymentMode.credit,
      subtotalInCents: 100000, // ₹1,000
      cgstInCents: 9000,       // ₹90
      sgstInCents: 9000,       // ₹90
      igstInCents: 0,
      taxInCents: 18000,       // ₹180
      totalAmountInCents: 118000, // ₹1,180
      placeOfSupplyStateCode: '29',
      items: const [
        VoucherItemModel(
          itemId: testItemId,
          itemName: 'Test Product',
          sku: 'SKU-TP-01',
          hsnCode: '8471',
          quantity: 1.0,
          unit: 'PCS',
          unitPriceInCents: 100000,
          taxRatePercent: 18.0,
          cgstInCents: 9000,
          sgstInCents: 9000,
          totalInCents: 118000,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await voucherRepo.createVoucher(salesVoucher);

    // VERIFY: Item Master Stock: 10 -> 9
    final itemAfterSale = await inventoryRepo.getItemById(testItemId);
    expect(itemAfterSale.currentStockQuantity, equals(9.0));

    // VERIFY: Stock Movement Outward logged in StockLedger
    final stockMovements = await inventoryRepo.getStockLedger(testItemId);
    expect(stockMovements.any((m) => m.transactionType == StockTransactionType.outward && m.quantity == 1.0), isTrue);

    // VERIFY: Customer Outstanding: ₹0 -> ₹1,180 (118000 cents debit / receivable)
    final customerAfterSale = await ledgerRepo.getPartyById(customerId);
    expect(customerAfterSale.netBalanceInCents, equals(118000));

    // VERIFY: Accounting Journal Lines for Sales Invoice (Double-Entry Verification)
    final journalsAfterSale = await ledgerRepo.getJournals();
    final saleJournal = journalsAfterSale.firstWhere((j) => j.voucherId == salesVoucher.id);
    expect(saleJournal.isBalanced, isTrue);
    expect(saleJournal.totalAmountInCents, equals(118000));

    final arLine = saleJournal.lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.arId));
    expect(arLine.debitInCents, equals(118000));
    expect(arLine.creditInCents, equals(0));

    final salesLine = saleJournal.lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.salesId));
    expect(salesLine.debitInCents, equals(0));
    expect(salesLine.creditInCents, equals(100000));

    // ==========================================
    // 4. POST CREDIT PURCHASE INVOICE
    // Test Product x 5 @ ₹600 + 18% GST = Total ₹3,540 (Taxable ₹3,000, Input GST ₹540)
    // ==========================================
    final purchaseVoucher = VoucherModel(
      id: 'vch_purchase_001',
      companyId: testCompanyId,
      voucherNumber: 'BILL-2026-001',
      type: VoucherType.purchase,
      status: VoucherStatus.posted,
      date: now,
      partyId: supplierId,
      partyName: supplier.name,
      paymentMode: PaymentMode.credit,
      subtotalInCents: 300000, // ₹3,000
      cgstInCents: 27000,      // ₹270
      sgstInCents: 27000,      // ₹270
      igstInCents: 0,
      taxInCents: 54000,       // ₹540
      totalAmountInCents: 354000, // ₹3,540
      placeOfSupplyStateCode: '29',
      items: const [
        VoucherItemModel(
          itemId: testItemId,
          itemName: 'Test Product',
          sku: 'SKU-TP-01',
          hsnCode: '8471',
          quantity: 5.0,
          unit: 'PCS',
          unitPriceInCents: 60000,
          taxRatePercent: 18.0,
          cgstInCents: 27000,
          sgstInCents: 27000,
          totalInCents: 354000,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await voucherRepo.createVoucher(purchaseVoucher);

    // VERIFY: Item Master Stock: 9 -> 14
    final itemAfterPurchase = await inventoryRepo.getItemById(testItemId);
    expect(itemAfterPurchase.currentStockQuantity, equals(14.0));

    // VERIFY: Supplier Payable: ₹0 -> -₹3,540 (-354000 cents credit / payable)
    final supplierAfterPurchase = await ledgerRepo.getPartyById(supplierId);
    expect(supplierAfterPurchase.netBalanceInCents, equals(-354000));

    // VERIFY: Accounting Journal Lines for Purchase Invoice
    final journalsAfterPur = await ledgerRepo.getJournals();
    final purJournal = journalsAfterPur.firstWhere((j) => j.voucherId == purchaseVoucher.id);
    expect(purJournal.isBalanced, isTrue);

    final purLine = purJournal.lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.purchasesCogsId));
    expect(purLine.debitInCents, equals(300000));

    final apLine = purJournal.lines.firstWhere((l) => l.accountId.endsWith(DefaultAccounts.apId));
    expect(apLine.creditInCents, equals(354000));

    // ==========================================
    // 5. POST CUSTOMER RECEIPT (Got money from Customer)
    // Customer pays ₹1,180 via Bank -> Cash/Bank DR ₹1,180, AR CR ₹1,180
    // ==========================================
    final receiptVoucher = VoucherModel(
      id: 'vch_receipt_001',
      companyId: testCompanyId,
      voucherNumber: 'REC-2026-001',
      type: VoucherType.receipt,
      status: VoucherStatus.posted,
      date: now,
      partyId: customerId,
      partyName: customer.name,
      paymentMode: PaymentMode.bank,
      totalAmountInCents: 118000,
      createdAt: now,
      updatedAt: now,
    );

    await voucherRepo.createVoucher(receiptVoucher);

    // VERIFY: Customer balance decreases from ₹1,180 -> ₹0 (Settled)
    final customerAfterReceipt = await ledgerRepo.getPartyById(customerId);
    expect(customerAfterReceipt.netBalanceInCents, equals(0));

    // ==========================================
    // 6. POST SUPPLIER PAYMENT (Gave money to Supplier)
    // Pay supplier ₹3,540 via Bank -> AP DR ₹3,540, Cash/Bank CR ₹3,540
    // ==========================================
    final paymentVoucher = VoucherModel(
      id: 'vch_payment_001',
      companyId: testCompanyId,
      voucherNumber: 'PAY-2026-001',
      type: VoucherType.payment,
      status: VoucherStatus.posted,
      date: now,
      partyId: supplierId,
      partyName: supplier.name,
      paymentMode: PaymentMode.bank,
      totalAmountInCents: 354000,
      createdAt: now,
      updatedAt: now,
    );

    await voucherRepo.createVoucher(paymentVoucher);

    // VERIFY: Supplier balance decreases from -₹3,540 -> ₹0 (Settled)
    final supplierAfterPayment = await ledgerRepo.getPartyById(supplierId);
    expect(supplierAfterPayment.netBalanceInCents, equals(0));

    // ==========================================
    // 7. POST SERVICE / NON-STOCK SALES INVOICE
    // Service line does NOT affect inventory stock
    // ==========================================
    final serviceVoucher = VoucherModel(
      id: 'vch_sales_service_001',
      companyId: testCompanyId,
      voucherNumber: 'INV-2026-002',
      type: VoucherType.sales,
      status: VoucherStatus.posted,
      date: now,
      partyId: customerId,
      partyName: customer.name,
      paymentMode: PaymentMode.credit,
      subtotalInCents: 500000, // ₹5,000
      cgstInCents: 45000,      // ₹450
      sgstInCents: 45000,      // ₹450
      taxInCents: 90000,       // ₹900 (CGST + SGST)
      totalAmountInCents: 590000, // ₹5,900
      items: const [
        VoucherItemModel(
          itemId: 'srv_cloud_consulting_9983', // Non-inventory service ID
          itemName: 'Cloud Architecture Advisory',
          sku: 'SRV-CLD',
          hsnCode: '9983',
          quantity: 1.0,
          unit: 'HRS',
          unitPriceInCents: 500000,
          taxRatePercent: 18.0,
          cgstInCents: 45000,
          sgstInCents: 45000,
          totalInCents: 590000,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    await voucherRepo.createVoucher(serviceVoucher);

    // VERIFY: Product Stock remains exactly 14.0 (Service line had NO stock impact!)
    final itemAfterService = await inventoryRepo.getItemById(testItemId);
    expect(itemAfterService.currentStockQuantity, equals(14.0));

    // Customer balance reflects the service invoice (₹5,900 outstanding)
    final customerLatest = await ledgerRepo.getPartyById(customerId);
    expect(customerLatest.netBalanceInCents, equals(590000));

    // ==========================================
    // 8. FINANCIAL STATEMENTS DOUBLE-ENTRY ENGINE VALIDATION
    // Trial Balance, Profit & Loss, Balance Sheet
    // ==========================================
    final allParties = [await ledgerRepo.getPartyById(customerId), await ledgerRepo.getPartyById(supplierId)];
    final allItems = [await inventoryRepo.getItemById(testItemId)];
    final allEntries = await ledgerRepo.getEntriesForParty(customerId);
    final allVouchers = [
      await voucherRepo.getVoucherById(salesVoucher.id),
      await voucherRepo.getVoucherById(purchaseVoucher.id),
      await voucherRepo.getVoucherById(receiptVoucher.id),
      await voucherRepo.getVoucherById(paymentVoucher.id),
      await voucherRepo.getVoucherById(serviceVoucher.id),
    ];

    // Trial Balance
    final tb = FinancialStatementEngine.generateTrialBalance(
      parties: allParties,
      vouchers: allVouchers,
      items: allItems,
    );
    expect(tb.summary['isBalanced'], isTrue, reason: 'Trial Balance must satisfy Total Debit == Total Credit');
    expect(tb.summary['totalDebit'], equals(tb.summary['totalCredit']));

    // Profit & Loss Statement
    final pnl = FinancialStatementEngine.generateProfitAndLoss(
      company: testCompany,
      vouchers: allVouchers,
      items: allItems,
      entries: allEntries,
    );
    expect(pnl.summary.containsKey('netProfit'), isTrue);
    expect(pnl.rows.any((r) => r.get('particulars') == 'Gross Revenue from Operations (Sales)'), isTrue);

    // Balance Sheet
    final bs = FinancialStatementEngine.generateBalanceSheet(
      company: testCompany,
      parties: allParties,
      items: allItems,
      entries: allEntries,
      vouchers: allVouchers,
    );
    expect(bs.summary['isBalanced'], isTrue, reason: 'Balance Sheet must balance Assets == Liabilities + Equity');

    // VERIFY: Accounts Receivable GL Account Balance matches Customer Subledger (₹5,900)
    final arAccount = await ledgerRepo.getAccountById('${testCompanyId}_${DefaultAccounts.arId}');
    expect(arAccount.currentBalanceInCents, equals(590000), reason: 'GL AR Account must match Customer Outstanding of ₹5,900');

    // VERIFY: Accounts Payable GL Account Balance matches Supplier Subledger (₹0)
    final apAccount = await ledgerRepo.getAccountById('${testCompanyId}_${DefaultAccounts.apId}');
    expect(apAccount.currentBalanceInCents, equals(0), reason: 'GL AP Account must match Supplier Balance of ₹0');
  });
}
