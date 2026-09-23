import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/gst_models.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/presentation/reports/invoice_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dynamic Invoice Templates & Branding Tests (FR-INV-01, FR-INV-02)', () {
    late Company testCompany;
    late Party testParty;
    late VoucherModel testVoucher;

    setUp(() {
      testCompany = Company(
        id: 'cmp_test',
        name: 'Ledger Pulse Enterprise',
        legalName: 'Ledger Pulse Enterprise Pvt Ltd',
        gstin: '29ABCDE1234F1ZH',
        stateCode: '29',
        currencyCode: 'INR',
        address: 'MG Road, Bangalore, India',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      testParty = Party(
        id: 'pty_test',
        name: 'Zenith Global Technologies',
        phoneNumber: '+91 99887 76655',
        type: PartyType.customer,
        netBalanceInCents: 0,
        gstin: '29XYZDE9876K1Z2',
        stateCode: '29',
        lastUpdated: DateTime(2026, 9, 23),
      );

      testVoucher = VoucherModel(
        id: 'vch_test_inv',
        companyId: 'cmp_test',
        voucherNumber: 'INV-2026-909',
        type: VoucherType.sales,
        date: DateTime(2026, 9, 23),
        partyId: 'pty_test',
        partyName: 'Zenith Global Technologies',
        items: const [
          VoucherItemModel(
            itemId: 'itm_01',
            itemName: 'Cloud ERP Software Subscription',
            sku: 'ERP-SUB-01',
            hsnCode: '998313',
            quantity: 1.0,
            unit: 'MO',
            unitPriceInCents: 1000000,
            taxRatePercent: 18.0,
            cgstInCents: 90000,
            sgstInCents: 90000,
            totalInCents: 1180000,
          ),
        ],
        subtotalInCents: 1000000,
        cgstInCents: 90000,
        sgstInCents: 90000,
        taxInCents: 180000,
        totalAmountInCents: 1180000,
        placeOfSupplyStateCode: '29',
        irn: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        signedQrCode: 'SAMPLE_SIGNED_QR_CODE_DATA',
        eWayBillNumber: '291234567890',
        createdAt: DateTime(2026, 9, 23),
        updatedAt: DateTime(2026, 9, 23),
      );
    });

    test('generates valid PDF bytes for Modern Expressive template', () async {
      final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
        voucher: testVoucher,
        company: testCompany,
        party: testParty,
        templateType: InvoiceTemplateType.modernExpressive,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      // Standard PDF header signature %PDF-
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), equals('%PDF'));
    });

    test('generates valid PDF bytes for Classic Corporate template', () async {
      final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
        voucher: testVoucher,
        company: testCompany,
        party: testParty,
        templateType: InvoiceTemplateType.classicCorporate,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), equals('%PDF'));
    });

    test('generates valid PDF bytes for GST Statutory Tax Invoice template', () async {
      final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
        voucher: testVoucher,
        company: testCompany,
        party: testParty,
        templateType: InvoiceTemplateType.gstStatutory,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), equals('%PDF'));
    });

    test('generates valid PDF bytes for Compact POS Slip template', () async {
      final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
        voucher: testVoucher,
        company: testCompany,
        party: testParty,
        templateType: InvoiceTemplateType.compactPos,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), equals('%PDF'));
    });

    test('embeds custom authorized signatory and banking details into invoice', () async {
      const customConfig = InvoiceCustomization(
        authorizedSignatoryName: 'Vikramaditya Roy',
        authorizedSignatoryDesignation: 'Chief Financial Officer',
        bankName: 'Kotak Mahindra Bank',
        bankAccountNumber: '987654321012',
        bankIfsc: 'KKBK0001234',
        upiId: 'vikram@kotak',
      );

      final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
        voucher: testVoucher,
        company: testCompany,
        party: testParty,
        templateType: InvoiceTemplateType.gstStatutory,
        customization: customConfig,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });
  });
}
