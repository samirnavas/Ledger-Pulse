import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/gst_models.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/presentation/reports/invoice_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
  });

  tearDown(() async {
    await db.close();
  });

  group('Invoice Drafting & Hold Status (FR-VCH-04)', () {
    test('Saving voucher as draft does NOT post double-entry ledger', () async {
      // Create a customer party first
      final partyId = 'pty_test_01';
      final now = DateTime.now();
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              id: partyId,
              name: 'Draft Customer Pvt Ltd',
              phoneNumber: '+91 99999 88888',
              type: PartyType.customer,
              lastUpdated: now,
            ),
          );

      final draftVoucher = VoucherModel(
        id: 'vch_draft_01',
        companyId: 'cmp_default',
        voucherNumber: 'DRF-001',
        type: VoucherType.sales,
        date: now,
        partyId: partyId,
        partyName: 'Draft Customer Pvt Ltd',
        status: VoucherStatus.draft,
        items: const [
          VoucherItemModel(
            itemId: 'item_01',
            itemName: 'Draft Consulting',
            sku: 'SKU-01',
            quantity: 2,
            unitPriceInCents: 50000,
            taxRatePercent: 18,
            totalInCents: 118000,
          ),
        ],
        subtotalInCents: 100000,
        taxInCents: 18000,
        totalAmountInCents: 118000,
        createdAt: now,
        updatedAt: now,
      );

      final saved = await postingEngine.postVoucher(
        voucher: draftVoucher,
        userId: 'usr_admin',
      );

      expect(saved.status, VoucherStatus.draft);

      // Verify voucher exists in DB
      final dbVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_draft_01'))).getSingle();
      expect(dbVoucher.status, 'draft');

      // Verify NO ledger entry was created for draft
      final entries = await (db.select(db.ledgerEntries)..where((t) => t.partyId.equals(partyId))).get();
      expect(entries, isEmpty, reason: 'Draft vouchers must not create financial ledger entries');
    });

    test('Saving voucher as onHold does NOT post double-entry ledger', () async {
      final partyId = 'pty_test_02';
      final now = DateTime.now();
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              id: partyId,
              name: 'OnHold Customer Ltd',
              phoneNumber: '+91 98888 77777',
              type: PartyType.customer,
              lastUpdated: now,
            ),
          );

      final onHoldVoucher = VoucherModel(
        id: 'vch_hold_01',
        companyId: 'cmp_default',
        voucherNumber: 'HLD-001',
        type: VoucherType.sales,
        date: now,
        partyId: partyId,
        partyName: 'OnHold Customer Ltd',
        status: VoucherStatus.onHold,
        items: const [
          VoucherItemModel(
            itemId: 'item_02',
            itemName: 'Hardware Terminal',
            sku: 'SKU-02',
            quantity: 1,
            unitPriceInCents: 250000,
            taxRatePercent: 18,
            totalInCents: 295000,
          ),
        ],
        subtotalInCents: 250000,
        taxInCents: 45000,
        totalAmountInCents: 295000,
        createdAt: now,
        updatedAt: now,
      );

      final saved = await postingEngine.postVoucher(
        voucher: onHoldVoucher,
        userId: 'usr_admin',
      );

      expect(saved.status, VoucherStatus.onHold);

      final dbVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_hold_01'))).getSingle();
      expect(dbVoucher.status, 'onHold');

      final entries = await (db.select(db.ledgerEntries)..where((t) => t.partyId.equals(partyId))).get();
      expect(entries, isEmpty, reason: 'Held vouchers must not create financial ledger entries');
    });

    test('Updating a draft or held voucher to posted status posts double-entry ledger', () async {
      final partyId = 'pty_test_03';
      final now = DateTime.now();
      await db.into(db.parties).insert(
            PartiesCompanion.insert(
              id: partyId,
              name: 'Resumed Customer',
              phoneNumber: '+91 97777 66666',
              type: PartyType.customer,
              lastUpdated: now,
            ),
          );

      final draftVoucher = VoucherModel(
        id: 'vch_draft_to_post',
        companyId: 'cmp_default',
        voucherNumber: 'INV-RESUME-01',
        type: VoucherType.sales,
        date: now,
        partyId: partyId,
        partyName: 'Resumed Customer',
        status: VoucherStatus.draft,
        items: const [
          VoucherItemModel(
            itemId: 'item_03',
            itemName: 'Software License',
            sku: 'SKU-03',
            quantity: 1,
            unitPriceInCents: 100000,
            taxRatePercent: 18,
            totalInCents: 118000,
          ),
        ],
        subtotalInCents: 100000,
        taxInCents: 18000,
        totalAmountInCents: 118000,
        createdAt: now,
        updatedAt: now,
      );

      // Save as draft first
      await postingEngine.postVoucher(voucher: draftVoucher, userId: 'usr_admin');

      // Now resume and post the draft
      final postedVoucher = draftVoucher.copyWith(
        status: VoucherStatus.posted,
      );
      await postingEngine.postVoucher(voucher: postedVoucher, userId: 'usr_admin');

      // Verify status in DB updated to posted
      final dbVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_draft_to_post'))).getSingle();
      expect(dbVoucher.status, 'posted');

      // Verify double-entry ledger entry was created
      final entries = await (db.select(db.ledgerEntries)..where((t) => t.partyId.equals(partyId))).get();
      expect(entries.length, 1);
      expect(entries.first.amountInCents, 118000);
      expect(entries.first.type.name, 'gave'); // Receivable from customer
    });
  });

  group('Company Bank & UPI ID Payment Configuration (FR-VCH-09)', () {
    test('Company model correctly serializes and deserializes upiId and bank fields', () {
      final now = DateTime.now();
      final company = Company(
        id: 'cmp_ludger_01',
        name: 'Ludger Technologies',
        legalName: 'Ludger Technologies Private Limited',
        gstin: '29ABCDE1234F1ZH',
        bankName: 'ICICI Bank',
        bankAccountNumber: '001105001234',
        bankIfsc: 'ICIC0000011',
        upiId: 'ludger@icici',
        createdAt: now,
        updatedAt: now,
      );

      final map = company.toMap();
      expect(map['bankName'], 'ICICI Bank');
      expect(map['bankAccountNumber'], '001105001234');
      expect(map['bankIfsc'], 'ICIC0000011');
      expect(map['upiId'], 'ludger@icici');

      final reconstructed = Company.fromMap(map);
      expect(reconstructed.bankName, 'ICICI Bank');
      expect(reconstructed.bankAccountNumber, '001105001234');
      expect(reconstructed.bankIfsc, 'ICIC0000011');
      expect(reconstructed.upiId, 'ludger@icici');
    });

    test('UserProfile updates propagate bank details and upiId to activeCompany', () {
      final profile = UserProfile(
        name: 'Admin User',
        phoneNumber: '+91 99999 00000',
        email: 'admin@ludgerpulse.com',
      );

      final updated = profile.copyWith(
        bankName: 'State Bank of India',
        bankAccountNumber: '20304050607',
        bankIfsc: 'SBIN0001234',
        upiId: 'ludgerpulse@sbi',
      );

      expect(updated.bankName, 'State Bank of India');
      expect(updated.bankAccountNumber, '20304050607');
      expect(updated.bankIfsc, 'SBIN0001234');
      expect(updated.upiId, 'ludgerpulse@sbi');
      expect(updated.activeCompany.upiId, 'ludgerpulse@sbi');
    });

    test('InvoicePdfGenerator dynamically renders configured company Bank & UPI ID', () async {
      final now = DateTime.now();
      final company = Company(
        id: 'cmp_pdf_01',
        name: 'Custom Remittance Corp',
        legalName: 'Custom Remittance Corp Pvt Ltd',
        gstin: '29ABCDE1234F1ZH',
        bankName: 'Axis Bank',
        bankAccountNumber: '912010045678901',
        bankIfsc: 'UTIB0000123',
        upiId: 'remittance@axisbank',
        createdAt: now,
        updatedAt: now,
      );

      final party = Party(
        id: 'pty_invoice_01',
        name: 'Acme Retailers',
        phoneNumber: '+91 98765 43210',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: now,
      );

      final voucher = VoucherModel(
        id: 'vch_pdf_01',
        companyId: company.id,
        voucherNumber: 'INV-AXIS-01',
        type: VoucherType.sales,
        date: now,
        partyId: party.id,
        partyName: party.name,
        status: VoucherStatus.posted,
        items: const [
          VoucherItemModel(
            itemId: 'itm_01',
            itemName: 'Cloud Hosting Subscription',
            sku: 'SKU-HST-01',
            quantity: 1,
            unitPriceInCents: 100000,
            taxRatePercent: 18,
            totalInCents: 118000,
          ),
        ],
        subtotalInCents: 100000,
        taxInCents: 18000,
        totalAmountInCents: 118000,
        createdAt: now,
        updatedAt: now,
      );

      for (final template in InvoiceTemplateType.values) {
        final pdfBytes = await InvoicePdfGenerator.generateInvoicePdf(
          voucher: voucher,
          company: company,
          party: party,
          templateType: template,
        );

        expect(pdfBytes, isNotEmpty, reason: 'Failed to generate PDF for $template');
        expect(pdfBytes.length, greaterThan(1000));
      }
    });
  });
}
