import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/reporting/gstr_json_engine.dart';

void main() {
  group('GSTR JSON Generation Engine Tests (FR-GST-03, FR-GST-04)', () {
    late Company testCompany;
    late Party b2bParty;
    late Party b2cParty;
    late List<VoucherModel> sampleSales;
    late List<VoucherModel> samplePurchases;

    setUp(() {
      testCompany = Company(
        id: 'cmp_default',
        name: 'Apex Industrial Solutions',
        legalName: 'Apex Industrial Solutions Pvt Ltd',
        gstin: '29ABCDE1234F1ZH',
        stateCode: '29',
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
      );

      b2bParty = Party(
        id: 'party_b2b',
        name: 'Omni Retailers Corp',
        phoneNumber: '+919876543210',
        type: PartyType.customer,
        gstin: '29XYZDE9876K1Z2',
        stateCode: '29',
        netBalanceInCents: 0,
        lastUpdated: DateTime(2026, 1, 1),
      );

      b2cParty = Party(
        id: 'party_b2c',
        name: 'Direct Retail Consumer',
        phoneNumber: '+919876500000',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime(2026, 1, 1),
      );

      sampleSales = [
        VoucherModel(
          id: 'vch_sale_b2b',
          companyId: 'cmp_default',
          voucherNumber: 'INV-2026-001',
          type: VoucherType.sales,
          partyId: b2bParty.id,
          partyName: b2bParty.name,
          date: DateTime(2026, 9, 15),
          subtotalInCents: 100000,
          cgstInCents: 9000,
          sgstInCents: 9000,
          igstInCents: 0,
          totalAmountInCents: 118000,
          placeOfSupplyStateCode: '29',
          items: const [
            VoucherItemModel(
              itemId: 'item_raw_1',
              itemName: 'Aluminium Extrusions',
              sku: 'SKU-EXT-1',
              hsnCode: '7604',
              unit: 'KG',
              quantity: 10,
              unitPriceInCents: 10000,
              taxRatePercent: 18.0,
              totalInCents: 118000,
            ),
          ],
          createdAt: DateTime(2026, 9, 15),
          updatedAt: DateTime(2026, 9, 15),
        ),
        VoucherModel(
          id: 'vch_sale_b2cs',
          companyId: 'cmp_default',
          voucherNumber: 'INV-2026-002',
          type: VoucherType.sales,
          partyId: b2cParty.id,
          partyName: b2cParty.name,
          date: DateTime(2026, 9, 18),
          subtotalInCents: 20000,
          cgstInCents: 1800,
          sgstInCents: 1800,
          igstInCents: 0,
          totalAmountInCents: 23600,
          placeOfSupplyStateCode: '29',
          items: const [
            VoucherItemModel(
              itemId: 'item_fin_1',
              itemName: 'Branded Fittings',
              sku: 'SKU-FIT-1',
              hsnCode: '7610',
              unit: 'PCS',
              quantity: 2,
              unitPriceInCents: 10000,
              taxRatePercent: 18.0,
              totalInCents: 23600,
            ),
          ],
          createdAt: DateTime(2026, 9, 18),
          updatedAt: DateTime(2026, 9, 18),
        ),
      ];

      samplePurchases = [
        VoucherModel(
          id: 'vch_pur_1',
          companyId: 'cmp_default',
          voucherNumber: 'PUR-2026-089',
          type: VoucherType.purchase,
          partyId: b2bParty.id,
          partyName: b2bParty.name,
          date: DateTime(2026, 9, 10),
          subtotalInCents: 50000,
          taxInCents: 9000,
          cgstInCents: 4500,
          sgstInCents: 4500,
          igstInCents: 0,
          totalAmountInCents: 59000,
          placeOfSupplyStateCode: '29',
          items: const [
            VoucherItemModel(
              itemId: 'item_ingot_1',
              itemName: 'Raw Ingot',
              sku: 'SKU-ING-1',
              hsnCode: '7601',
              unit: 'KG',
              quantity: 5,
              unitPriceInCents: 10000,
              taxRatePercent: 18.0,
              totalInCents: 59000,
            ),
          ],
          createdAt: DateTime(2026, 9, 10),
          updatedAt: DateTime(2026, 9, 10),
        ),
      ];
    });

    test('GSTR-1 JSON correctly partitions B2B and B2CS supplies and outputs HSN summary', () {
      final gstr1 = GstrJsonEngine.generateGstr1Json(
        company: testCompany,
        salesVouchers: sampleSales,
        parties: [b2bParty, b2cParty],
        returnPeriod: '092026',
        previousYearGrossTurnover: 25000000.0,
      );

      expect(gstr1['gstin'], equals('29ABCDE1234F1ZH'));
      expect(gstr1['fp'], equals('092026'));
      expect(gstr1['gt'], equals(25000000.0));

      // B2B Section
      final b2b = gstr1['b2b'] as List;
      expect(b2b.length, equals(1));
      expect(b2b.first['ctin'], equals('29XYZDE9876K1Z2'));
      final invList = b2b.first['inv'] as List;
      expect(invList.length, equals(1));
      expect(invList.first['inum'], equals('INV-2026-001'));
      expect(invList.first['val'], equals(1180.0));

      // B2CS Section
      final b2cs = gstr1['b2cs'] as List;
      expect(b2cs.length, equals(1));
      expect(b2cs.first['pos'], equals('29'));
      expect(b2cs.first['txval'], equals(200.0));

      // HSN Summary Section
      final hsnData = gstr1['hsn']['data'] as List;
      expect(hsnData.length, equals(2));
      final hsnCodes = hsnData.map((e) => e['hsn_sc']).toList();
      expect(hsnCodes, containsAll(['7604', '7610']));

      // Doc Issue Section
      final docDet = gstr1['doc_issue']['doc_det'] as List;
      expect(docDet.isNotEmpty, isTrue);
      final docs = docDet.first['doc_det'] as List;
      expect(docs.first['doc_num'], equals(1));
      expect(docs.first['totnum'], equals(2));
    });

    test('GSTR-2 JSON correctly groups inward purchases and input tax credit (ITC)', () {
      final gstr2 = GstrJsonEngine.generateGstr2Json(
        company: testCompany,
        purchaseVouchers: samplePurchases,
        parties: [b2bParty],
        returnPeriod: '092026',
      );

      expect(gstr2['gstin'], equals('29ABCDE1234F1ZH'));
      expect(gstr2['fp'], equals('092026'));

      final b2b = gstr2['b2b'] as List;
      expect(b2b.length, equals(1));
      expect(b2b.first['ctin'], equals('29XYZDE9876K1Z2'));

      final inv = b2b.first['inv'].first;
      expect(inv['inum'], equals('PUR-2026-089'));
      expect(inv['val'], equals(590.0));

      final itc = inv['itms'].first['itc'];
      expect(itc['elg'], equals('ip'));
      expect(itc['tx_c'], equals(45.0));
      expect(itc['tx_s'], equals(45.0));
    });

    test('GSTR-2A reconciliation correctly reconciles matched, mismatched, and missing invoices', () {
      final portalFeed = [
        {
          'inum': 'PUR-2026-089',
          'val': 590.0,
          'supplierGstin': '29XYZDE9876K1Z2',
        },
        {
          'inum': 'PUR-PORTAL-ONLY-99',
          'val': 1200.0,
          'supplierGstin': '29SUPP9999Z1',
        },
      ];

      final recon = GstrJsonEngine.generateGstr2aReconciliationJson(
        booksPurchases: samplePurchases,
        portal2aFeed: portalFeed,
      );

      final summary = recon['summary'] as Map<String, dynamic>;
      expect(summary['totalMatched'], equals(1));
      expect(summary['totalMissingInBooks'], equals(1));
      expect(summary['totalMissingInPortal'], equals(0));

      final matched = recon['matched'] as List;
      expect(matched.first['inum'], equals('PUR-2026-089'));
      expect(matched.first['status'], equals('MATCHED'));

      final missingInBooks = recon['missingInBooks'] as List;
      expect(missingInBooks.first['inum'], equals('PUR-PORTAL-ONLY-99'));
    });

    test('GSTR-3B JSON aggregates outward supplies and eligible ITC', () {
      final gstr3b = GstrJsonEngine.generateGstr3bJson(
        company: testCompany,
        salesVouchers: sampleSales,
        purchaseVouchers: samplePurchases,
        returnPeriod: '092026',
      );

      expect(gstr3b['gstin'], equals('29ABCDE1234F1ZH'));
      expect(gstr3b['ret_period'], equals('092026'));

      final osup = gstr3b['sup_details']['osup_det'];
      // Total taxable = (100000 + 20000) / 100 = 1200.0
      expect(osup['txval'], equals(1200.0));
      expect(osup['camt'], equals(108.0));
      expect(osup['samt'], equals(108.0));

      final itc = gstr3b['itc_elg']['itc_avl'].first;
      // Eligible ITC from purchases = (4500 + 4500) / 100
      expect(itc['camt'], equals(45.0));
      expect(itc['samt'], equals(45.0));
    });

    test('GSTR-4 Composition and GSTR-9 Annual Return payloads are populated accurately', () {
      final gstr4 = GstrJsonEngine.generateGstr4Json(
        company: testCompany,
        vouchers: sampleSales,
        financialYear: '2026-27',
      );

      expect(gstr4['gstin'], equals('29ABCDE1234F1ZH'));
      expect(gstr4['turnover_details']['total_turnover'], equals(1416.0));

      final gstr9 = GstrJsonEngine.generateGstr9Json(
        company: testCompany,
        salesVouchers: sampleSales,
        purchaseVouchers: samplePurchases,
        financialYear: '2026-27',
      );

      expect(gstr9['fp'], equals('2026-27'));
      expect(gstr9['part2_outward_supplies']['total_turnover'], equals(1200.0));
      expect(gstr9['part3_itc_details']['itc_availed'], equals(90.0));
    });
  });
}
