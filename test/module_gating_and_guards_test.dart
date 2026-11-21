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

  test('legacy imports remain available while ERP services are disabled', () {
    final company = _createTestCompany(id: 'legacy', name: 'Legacy', enabledModules: AppModule.allModules);
    expect(() => DataImportService.verifyModuleEnabled(company), returnsNormally);
    expect(() => EcommerceSyncService.syncAmazonIndiaOrders(jsonPayload: '{}', company: company), throwsA(isA<ModuleDisabledException>()));
  });

  group('UI and Deep Link Gating Tests', () {
    test('ledger navigation defaults to Parties and has three destinations', () {
      final container = ProviderContainer(
        overrides: [activeCompanyIdProvider.overrideWithValue('ledger-test')],
      );
      addTearDown(container.dispose);
      expect(container.read(dashboardTabProvider), 0);
      final tabs = container.read(dashboardTabProvider.notifier);
      tabs.setTab(2);
      expect(container.read(dashboardTabProvider), 2);
      tabs.setTab(9);
      expect(container.read(dashboardTabProvider), 2);
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
