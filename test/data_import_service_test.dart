import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/services/data_import_service.dart';

void main() {
  group('Third-Party Data Importer Tests (FR-SYN-03)', () {
    const companyId = 'cmp_import_test';

    test('parseTallyXml extracts customers, suppliers, opening balances, and stock items', () {
      const tallyXml = '''<ENVELOPE>
  <BODY>
    <DATA>
      <TALLYMESSAGE>
        <LEDGER NAME="Apex Infotech Solutions">
          <PARENT>Sundry Debtors</PARENT>
          <PARTYGSTIN>29ABCDE1234F1ZH</PARTYGSTIN>
          <LEDGERPHONE>+91 98765 43210</LEDGERPHONE>
          <OPENINGBALANCE>150000.00</OPENINGBALANCE>
        </LEDGER>
        <LEDGER NAME="Karnataka Silicon Vendors">
          <PARENT>Sundry Creditors</PARENT>
          <PARTYGSTIN>29XYZDE9876K1Z2</PARTYGSTIN>
          <LEDGERPHONE>+91 98220 55443</LEDGERPHONE>
          <OPENINGBALANCE>45000.00</OPENINGBALANCE>
        </LEDGER>
        <STOCKITEM NAME="Industrial Control Unit MK-4">
          <BASEUNITS>PCS</BASEUNITS>
          <OPENINGBALANCE>25.0</OPENINGBALANCE>
          <OPENINGRATE>12500.00</OPENINGRATE>
          <HSNCODE>8471</HSNCODE>
        </STOCKITEM>
      </TALLYMESSAGE>
    </DATA>
  </BODY>
</ENVELOPE>''';

      final result = DataImportService.parseTallyXml(
        xmlContent: tallyXml,
        companyId: companyId,
      );

      expect(result.importedParties.length, equals(2));
      expect(result.importedItems.length, equals(1));

      final debtor = result.importedParties.firstWhere((p) => p.name == 'Apex Infotech Solutions');
      expect(debtor.type, equals(PartyType.customer));
      expect(debtor.gstin, equals('29ABCDE1234F1ZH'));
      expect(debtor.netBalanceInCents, equals(15000000)); // ₹1,50,000

      final creditor = result.importedParties.firstWhere((p) => p.name == 'Karnataka Silicon Vendors');
      expect(creditor.type, equals(PartyType.supplier));
      expect(creditor.gstin, equals('29XYZDE9876K1Z2'));

      final item = result.importedItems.first;
      expect(item.name, equals('Industrial Control Unit MK-4'));
      expect(item.currentStockQuantity, equals(25.0));
      expect(item.purchasePriceInCents, equals(1250000)); // ₹12,500
      expect(item.hsnCode, equals('8471'));
    });

    test('parseZohoCsv extracts contact records with proper types and GSTINs', () {
      const zohoCsv = '''Contact Name,Display Name,Contact Type,Phone,GST Identification Number (GSTIN)
"BlueStar Logistics Pvt Ltd","BlueStar Logistics","Customer","9844011223","29AAACB1122D1Z5"
"National Hardware Supplies","National Hardware","Vendor","9711099887","29BCCCD3344E1Z8"''';

      final result = DataImportService.parseZohoCsv(
        csvContent: zohoCsv,
        companyId: companyId,
      );

      expect(result.importedParties.length, equals(2));
      expect(result.importedParties[0].name, equals('BlueStar Logistics Pvt Ltd'));
      expect(result.importedParties[0].type, equals(PartyType.customer));
      expect(result.importedParties[1].name, equals('National Hardware Supplies'));
      expect(result.importedParties[1].type, equals(PartyType.supplier));
    });

    test('parseQuickBooksIif extracts customer, vendor, and item records', () {
      const qbIif = '''!CUST	NAME	BADDR1	PHONE
CUST	Horizon Tech Innovations	MG Road Bangalore	9876501234
!VEND	NAME	BADDR1	PHONE
VEND	Southern Power Corp	Indiranagar	9823098765
!INVITEM	NAME	DESC	PRICE	COST
INVITEM	Server Rack Cabinet	42U Server Rack	45000	32000''';

      final result = DataImportService.parseQuickBooksIif(
        iifContent: qbIif,
        companyId: companyId,
      );

      expect(result.importedParties.length, equals(2));
      expect(result.importedItems.length, equals(1));
      expect(result.importedItems[0].name, equals('Server Rack Cabinet'));
      expect(result.importedItems[0].sellingPriceInCents, equals(4500000));
      expect(result.importedItems[0].purchasePriceInCents, equals(3200000));
    });

    test('parseExcelCsvAutoMapped intelligently detects and maps columns', () {
      const excelCsv = '''Customer Name,Phone,GSTIN,Opening Balance
"Prime Global Technologies","9811022334","29AAECP1234H1Z1","120000"
"Metro Retail Emporium","9822033445","29BBECP5678J1Z2","85000"''';

      final result = DataImportService.parseExcelCsvAutoMapped(
        csvContent: excelCsv,
        companyId: companyId,
      );

      expect(result.importedParties.length, equals(2));
      expect(result.importedParties[0].name, equals('Prime Global Technologies'));
      expect(result.importedParties[0].netBalanceInCents, equals(12000000));
      expect(result.importedParties[1].name, equals('Metro Retail Emporium'));
    });
  });
}
