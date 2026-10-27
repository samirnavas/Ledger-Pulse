import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/manufacturing_journal_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_inventory_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/models/manufacturing_bom_model.dart';
import 'package:ledger_pulse/data/models/payroll_model.dart';
import 'package:ledger_pulse/data/models/stock_ledger_model.dart';
import 'package:ledger_pulse/data/reporting/custom_sql_report_engine.dart';
import 'package:ledger_pulse/data/services/cts2010_cheque_printer_service.dart';
import 'package:ledger_pulse/data/services/data_import_service.dart';
import 'package:ledger_pulse/data/services/ecommerce_sync_service.dart';
import 'package:ledger_pulse/data/services/payroll_service.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';
import 'package:ledger_pulse/presentation/home/dashboard_screen.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/module_providers.dart';

Company _createTestCompany({
  required String id,
  required String name,
  CompanyMode mode = CompanyMode.ledger,
  Set<AppModule>? enabledModules,
}) {
  final now = DateTime.now();
  return Company(
    id: id,
    name: name,
    legalName: '$name Ltd',
    mode: mode,
    enabledModules: enabledModules ?? AppModule.allModules,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('ModuleDisabledException Tests', () {
    test('ModuleDisabledException holds the disabled AppModule and provides clear message', () {
      final ex = ModuleDisabledException(AppModule.payroll);
      expect(ex.module, equals(AppModule.payroll));
      expect(ex.toString(), contains('payroll'));
      expect(ex.toString(), contains('disabled'));
    });
  });

  group('Write Entry Point Module Guards', () {
    test('PayrollService guards throw ModuleDisabledException when payroll is disabled', () {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_payroll',
        name: 'No Payroll Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      final employee = Employee(
        id: 'emp_1',
        companyId: disabledCompany.id,
        employeeCode: 'EMP001',
        fullName: 'John Doe',
        phoneNumber: '9876543210',
        designation: 'Accountant',
        department: 'Finance',
        dateOfJoining: DateTime.now(),
        basicMonthlySalaryInCents: 5000000,
        hraAllowanceInCents: 2000000,
        specialAllowanceInCents: 1000000,
        conveyanceAllowanceInCents: 500000,
      );

      expect(
        () => PayrollService.processBulkPayroll(
          company: disabledCompany,
          employees: [employee],
          monthYear: '102026',
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.payroll)),
      );

      final batch = PayrollBatchResult(
        monthYear: '102026',
        totalEmployeesProcessed: 1,
        totalGrossInCents: 8500000,
        totalPfInCents: 600000,
        totalEsiInCents: 0,
        totalProfTaxInCents: 20000,
        totalTdsInCents: 0,
        totalNetPayoutInCents: 7880000,
        slips: [],
      );

      expect(
        () => PayrollService.createPayrollJournalVoucher(
          company: disabledCompany,
          batchResult: batch,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.payroll)),
      );
    });

    test('ManufacturingJournalEngine throws ModuleDisabledException when manufacturing is disabled', () async {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_mfg',
        name: 'No Mfg Co',
        enabledModules: {AppModule.parties, AppModule.vouchers, AppModule.inventory},
      );

      final engine = ManufacturingJournalEngine(db, AuditService(db));

      final bom = BillOfMaterials(
        id: 'bom_1',
        companyId: disabledCompany.id,
        bomName: 'Assembly',
        finishedGoodsItemId: 'itm_fg_1',
        finishedGoodsSku: 'FG-001',
        finishedGoodsName: 'Finished Good',
        outputQuantity: 1.0,
        rawMaterials: [],
        createdAt: DateTime.now(),
      );

      expect(
        () => engine.executeProductionRun(
          bom: bom,
          productionQuantity: 5.0,
          companyId: disabledCompany.id,
          userId: 'usr_1',
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.manufacturing)),
      );
    });

    test('DriftInventoryRepository throws ModuleDisabledException when inventory is disabled', () async {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_inv',
        name: 'No Inv Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      final invRepo = DriftInventoryRepository(
        db: db,
        currentCompanyId: disabledCompany.id,
      );
      invRepo.setContext(company: disabledCompany);

      final item = InventoryItem(
        id: 'itm_test_1',
        companyId: disabledCompany.id,
        sku: 'SKU-001',
        name: 'Test Item',
        purchasePriceInCents: 1000,
        sellingPriceInCents: 1500,
        currentStockQuantity: 10,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => invRepo.addItem(item, company: disabledCompany),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.inventory)),
      );

      expect(
        () => invRepo.updateItem(item, company: disabledCompany),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.inventory)),
      );

      expect(
        () => invRepo.adjustStock(
          itemId: item.id,
          quantityDelta: 5.0,
          type: StockTransactionType.inward,
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.inventory)),
      );
    });

    test('EcommerceSyncService throws ModuleDisabledException when ecommerceSync is disabled', () {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_ecom',
        name: 'No Ecom Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      expect(
        () => EcommerceSyncService.syncAmazonIndiaOrders(
          jsonPayload: '{"Orders":[]}',
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.ecommerceSync)),
      );

      expect(
        () => EcommerceSyncService.syncFlipkartOrders(
          jsonPayload: '{"orderItems":[]}',
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.ecommerceSync)),
      );
    });

    test('DataImportService throws ModuleDisabledException when dataImport is disabled', () {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_import',
        name: 'No Import Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      expect(
        () => DataImportService.verifyModuleEnabled(disabledCompany),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.dataImport)),
      );

      expect(
        () => DataImportService.parseTallyXml(
          xmlContent: '<ENVELOPE></ENVELOPE>',
          companyId: disabledCompany.id,
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.dataImport)),
      );

      expect(
        () => DataImportService.parseExcelCsvAutoMapped(
          csvContent: 'name,phone\nAcme,9999999999',
          companyId: disabledCompany.id,
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.dataImport)),
      );
    });

    test('CustomSqlReportEngine throws ModuleDisabledException when sqlStudio is disabled', () async {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_sql',
        name: 'No SQL Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      final engine = CustomSqlReportEngine(db);

      expect(
        () => engine.executeRawSql(
          sqlQuery: 'SELECT 1;',
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.sqlStudio)),
      );
    });

    test('Cts2010ChequePrinterService throws ModuleDisabledException when chequePrinting is disabled', () async {
      final disabledCompany = _createTestCompany(
        id: 'cmp_no_cheque',
        name: 'No Cheque Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      expect(
        () => Cts2010ChequePrinterService.generateChequePdf(
          payeeName: 'Vendor X',
          amountInCents: 500000,
          chequeDate: DateTime.now(),
          companyName: disabledCompany.name,
          company: disabledCompany,
        ),
        throwsA(isA<ModuleDisabledException>().having((e) => e.module, 'module', AppModule.chequePrinting)),
      );
    });
  });

  group('Legacy Company Invariance Tests (All Modules Enabled by Default)', () {
    test('legacy company with null enabledModulesJson has all 13 modules enabled', () {
      final legacyCompany = Company.fromMap({
        'id': 'cmp_legacy',
        'name': 'Legacy Enterprise',
        'legalName': 'Legacy Enterprise Ltd',
        'mode': 'ledger',
        'enabledModules': null, // legacy DB row has null enabledModules
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      for (final module in AppModule.values) {
        expect(
          legacyCompany.isModuleEnabled(module),
          isTrue,
          reason: 'Legacy company must have ${module.name} enabled',
        );
      }
    });

    test('legacy company executes writes without throwing ModuleDisabledException', () async {
      final legacyCompany = _createTestCompany(
        id: 'cmp_legacy_full',
        name: 'Legacy Co',
        enabledModules: AppModule.allModules,
      );

      // 1. Payroll write
      final employee = Employee(
        id: 'emp_leg_1',
        companyId: legacyCompany.id,
        employeeCode: 'LEG01',
        fullName: 'Jane Doe',
        phoneNumber: '9123456789',
        designation: 'Manager',
        department: 'Operations',
        dateOfJoining: DateTime.now(),
        basicMonthlySalaryInCents: 4000000,
        hraAllowanceInCents: 1500000,
        specialAllowanceInCents: 500000,
        conveyanceAllowanceInCents: 200000,
      );

      final batch = PayrollService.processBulkPayroll(
        company: legacyCompany,
        employees: [employee],
        monthYear: '102026',
      );
      expect(batch.totalEmployeesProcessed, equals(1));

      final voucher = PayrollService.createPayrollJournalVoucher(
        company: legacyCompany,
        batchResult: batch,
      );
      expect(voucher.companyId, equals(legacyCompany.id));

      // 2. Inventory write
      final invRepo = DriftInventoryRepository(
        db: db,
        currentCompanyId: legacyCompany.id,
      );
      invRepo.setContext(company: legacyCompany);

      final item = InventoryItem(
        id: 'itm_legacy_1',
        companyId: legacyCompany.id,
        sku: 'LEG-SKU',
        name: 'Legacy Product',
        purchasePriceInCents: 2000,
        sellingPriceInCents: 3000,
        currentStockQuantity: 50,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final added = await invRepo.addItem(item, company: legacyCompany);
      expect(added.id, equals(item.id));

      // 3. E-commerce write
      final syncResult = EcommerceSyncService.syncAmazonIndiaOrders(
        jsonPayload: jsonEncode({
          'Orders': [
            {
              'AmazonOrderId': '402-1234567-1234567',
              'OrderTotal': {'Amount': '1500.00'},
              'BuyerInfo': {'BuyerName': 'Test Buyer'},
              'PurchaseDate': '2026-10-27T10:00:00Z',
            }
          ]
        }),
        company: legacyCompany,
      );
      expect(syncResult.totalOrdersFetched, equals(1));

      // 4. Data Import check
      expect(() => DataImportService.verifyModuleEnabled(legacyCompany), returnsNormally);

      // 5. Cheque PDF write
      final pdfBytes = await Cts2010ChequePrinterService.generateChequePdf(
        payeeName: 'Legacy Supplier',
        amountInCents: 125000,
        chequeDate: DateTime.now(),
        companyName: legacyCompany.name,
        company: legacyCompany,
      );
      expect(pdfBytes.isNotEmpty, isTrue);
    });
  });

  group('UI and Deep Link Gating Tests', () {
    test('DashboardTabNotifier resolves to 2 (Profile tab) when parties module is disabled', () {
      final container = ProviderContainer(
        overrides: [
          activeCompanyProvider.overrideWithValue(
            _createTestCompany(
              id: 'cmp_no_parties',
              name: 'No Parties Co',
              enabledModules: {AppModule.vouchers, AppModule.inventory},
            ),
          ),
          moduleEnabledProvider(AppModule.parties).overrideWithValue(false),
        ],
      );

      final tab = container.read(dashboardTabProvider);
      expect(tab, equals(2), reason: 'When parties is disabled, default tab must be 2 (Profile)');

      // Attempting to switch to tab 0 (customers) clamps to tab 2
      container.read(dashboardTabProvider.notifier).setTab(0);
      expect(container.read(dashboardTabProvider), equals(2));

      container.dispose();
    });

    test('DashboardTabNotifier resolves to 0 when parties module is enabled', () {
      final container = ProviderContainer(
        overrides: [
          activeCompanyProvider.overrideWithValue(
            _createTestCompany(
              id: 'cmp_with_parties',
              name: 'With Parties Co',
              enabledModules: {AppModule.parties, AppModule.vouchers},
            ),
          ),
          moduleEnabledProvider(AppModule.parties).overrideWithValue(true),
        ],
      );

      final tab = container.read(dashboardTabProvider);
      expect(tab, equals(0), reason: 'When parties is enabled, default tab should be 0');

      container.dispose();
    });

    test('AppModule.fromName parses correctly and validates enabled state', () {
      expect(AppModule.fromName('payroll'), equals(AppModule.payroll));
      expect(AppModule.fromName('manufacturing'), equals(AppModule.manufacturing));
      expect(AppModule.fromName('invalid_module'), isNull);

      final testCompany = _createTestCompany(
        id: 'cmp_dl_test',
        name: 'Deep Link Test Co',
        enabledModules: {AppModule.parties, AppModule.vouchers},
      );

      final parsed = AppModule.fromName('payroll');
      expect(testCompany.isModuleEnabled(parsed!), isFalse);

      final parsedVouchers = AppModule.fromName('vouchers');
      expect(testCompany.isModuleEnabled(parsedVouchers!), isTrue);
    });
  });
}
