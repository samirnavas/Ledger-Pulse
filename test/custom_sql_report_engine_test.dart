import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/reporting/custom_sql_report_engine.dart';
import 'package:ledger_pulse/data/reporting/report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Custom SQL Report Engine & XML Templates Tests (FR-RPT-04)', () {
    late AppDatabase db;
    late CustomSqlReportEngine engine;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      engine = CustomSqlReportEngine(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('parses XML templates with metadata and column schema specifications', () {
      const xml = '''
<reports>
  <report id="rpt_test_parties" title="Customer Accounts">
    <description>Lists all customers and outstanding amounts</description>
    <query>
      SELECT name, phone_number, net_balance_in_cents FROM parties;
    </query>
    <columns>
      <column key="name" label="Party Name" />
      <column key="phone_number" label="Phone" />
      <column key="net_balance_in_cents" label="Balance" isNumeric="true" isCurrency="true" />
    </columns>
  </report>
</reports>
''';

      final templates = CustomSqlReportEngine.parseXmlTemplates(xml);
      expect(templates.length, equals(1));

      final tpl = templates.first;
      expect(tpl.id, equals('rpt_test_parties'));
      expect(tpl.title, equals('Customer Accounts'));
      expect(tpl.columns.length, equals(3));
      expect(tpl.columns[2].isNumeric, isTrue);
      expect(tpl.columns[2].isCurrency, isTrue);
    });

    test('executes custom SELECT query and returns formatted ReportData', () async {
      // Insert sample party directly into Drift DB
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              id: 'p_test_1',
              name: 'Industrial Tooling Corp',
              phoneNumber: '+919876543210',
              type: PartyType.customer,
              netBalanceInCents: const Value(50000),
              lastUpdated: DateTime.now(),
            ),
          );

      final report = await engine.executeRawSql(
        sqlQuery: "SELECT name, phone_number, net_balance_in_cents FROM parties WHERE id = 'p_test_1';",
        reportTitle: 'Test Party Query',
      );

      expect(report.rows.length, equals(1));
      expect(report.rows.first.get('name'), equals('Industrial Tooling Corp'));
      expect(report.rows.first.get('net_balance_in_cents'), equals(50000));
      expect(report.summary['totalRecordsFound'], equals(1));
    });

    test('strictly rejects destructive or modifying SQL queries (DELETE, DROP, INSERT, UPDATE)', () async {
      expect(
        () => engine.executeRawSql(sqlQuery: 'DELETE FROM parties;'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => engine.executeRawSql(sqlQuery: 'DROP TABLE vouchers;'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => engine.executeRawSql(sqlQuery: 'UPDATE parties SET net_balance_in_cents = 0;'),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => engine.executeRawSql(sqlQuery: 'INSERT INTO parties (id) VALUES ("hacked");'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ReportExportService exports ReportData to Excel CSV with UTF-8 BOM and generates PDF', () async {
      final report = await engine.executeRawSql(
        sqlQuery: "SELECT 'Apex' as name, 100 as total;",
        reportTitle: 'Sample Report Export',
      );

      final company = Company(
        id: 'cmp_default',
        name: 'Apex Industrial Solutions',
        legalName: 'Apex Industrial Solutions Pvt Ltd',
        gstin: '29ABCDE1234F1ZH',
        stateCode: '29',
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );

      // 1. Excel CSV Export
      final csvFile = await ReportExportService.exportToExcelCsv(
        report: report,
        company: company,
      );

      expect(csvFile.existsSync(), isTrue);
      final csvBytes = await csvFile.readAsBytes();
      expect(csvBytes.take(3), equals([0xEF, 0xBB, 0xBF])); // UTF-8 BOM for Microsoft Excel
      final csvContent = await csvFile.readAsString();
      expect(csvContent.contains('Apex Industrial Solutions'), isTrue);
      expect(csvContent.contains('"Apex","100"'), isTrue);

      // 2. Landscape PDF Generation
      final pdfBytes = await ReportExportService.generateReportPdf(
        report: report,
        company: company,
      );

      expect(pdfBytes.isNotEmpty, isTrue);
      // PDF header signature check '%PDF-'
      expect(String.fromCharCodes(pdfBytes.take(5)), equals('%PDF-'));
    });
  });
}
