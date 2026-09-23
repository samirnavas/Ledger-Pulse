import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/gst_models.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/einvoice_ewaybill_service.dart';

void main() {
  group('e-Invoice & e-Way Bill Compliance Tests (FR-GST-05, FR-GST-06)', () {
    late EInvoiceEWayBillService service;

    setUp(() {
      service = EInvoiceEWayBillService(
        initialQuota: const SubscriptionQuota(
          tierName: 'Growth',
          eInvoicesUsedThisMonth: 10,
          eInvoicesMonthlyQuota: 50,
          eWayBillsUsedThisMonth: 5,
          eWayBillsMonthlyQuota: 50,
        ),
      );
    });

    test('enforces 2026 GSTN 30-day reporting requirement for e-invoices', () async {
      final now = DateTime(2026, 9, 23);

      // 1. Valid: Invoice dated 10 days ago
      final validVoucher = VoucherModel(
        id: 'vch_valid',
        companyId: 'cmp_default',
        voucherNumber: 'INV-2026-001',
        type: VoucherType.sales,
        date: now.subtract(const Duration(days: 10)),
        totalAmountInCents: 100000,
        createdAt: now,
        updatedAt: now,
      );

      final validResult = await service.generateEInvoice(
        voucher: validVoucher,
        supplierGstin: '29ABCDE1234F1ZH',
        buyerGstin: '29XYZDE9876K1Z2',
        overrideNow: now,
      );

      expect(validResult.success, isTrue);
      expect(validResult.details, isNotNull);
      expect(validResult.details!.irn.length, equals(64)); // SHA-256 hash
      expect(validResult.details!.signedQrCode, isNotEmpty);
      expect(service.currentQuota.eInvoicesUsedThisMonth, equals(11));

      // 2. Violation: Invoice dated 35 days ago (Exceeds 30-day reporting limit)
      final expiredVoucher = VoucherModel(
        id: 'vch_expired',
        companyId: 'cmp_default',
        voucherNumber: 'INV-2026-OLD',
        type: VoucherType.sales,
        date: now.subtract(const Duration(days: 35)),
        totalAmountInCents: 100000,
        createdAt: now,
        updatedAt: now,
      );

      final expiredResult = await service.generateEInvoice(
        voucher: expiredVoucher,
        supplierGstin: '29ABCDE1234F1ZH',
        buyerGstin: '29XYZDE9876K1Z2',
        overrideNow: now,
      );

      expect(expiredResult.success, isFalse);
      expect(expiredResult.errorMessage, contains('2026 GSTN regulations'));
      expect(expiredResult.errorMessage, contains('30 days'));
      // Quota should NOT have been decremented
      expect(service.currentQuota.eInvoicesUsedThisMonth, equals(11));
    });

    test('enforces Bill-To / Ship-To statutory URP designation for unregistered consignees', () async {
      final now = DateTime(2026, 9, 23);
      final voucher = VoucherModel(
        id: 'vch_ship',
        companyId: 'cmp_default',
        voucherNumber: 'INV-EWB-01',
        type: VoucherType.sales,
        date: now,
        totalAmountInCents: 500000,
        createdAt: now,
        updatedAt: now,
      );

      // 1. Success with statutory "URP" designation
      final urpResult = await service.generateEWayBill(
        voucher: voucher,
        supplierGstin: '29ABCDE1234F1ZH',
        isBillToShipToDifferent: true,
        shipToGstinOrUrp: 'URP',
        overrideNow: now,
      );
      expect(urpResult.success, isTrue);
      expect(urpResult.details!.eWayBillNumber.length, equals(12));
      expect(urpResult.details!.shipToGstinOrUrp, equals('URP'));

      // 2. Success with valid 15-char Ship-To GSTIN
      final gstinResult = await service.generateEWayBill(
        voucher: voucher,
        supplierGstin: '29ABCDE1234F1ZH',
        isBillToShipToDifferent: true,
        shipToGstinOrUrp: '29ABCDE1234F1ZH',
        overrideNow: now,
      );
      expect(gstinResult.success, isTrue);

      // 3. Failure: Invalid random string provided for unregistered party
      final invalidResult = await service.generateEWayBill(
        voucher: voucher,
        supplierGstin: '29ABCDE1234F1ZH',
        isBillToShipToDifferent: true,
        shipToGstinOrUrp: 'UNREGISTERED_PARTY',
        overrideNow: now,
      );
      expect(invalidResult.success, isFalse);
      expect(invalidResult.errorMessage, contains('URP'));
    });

    test('enforces subscription quota limits and prevents overage', () async {
      final exhaustedService = EInvoiceEWayBillService(
        initialQuota: const SubscriptionQuota(
          tierName: 'Free',
          eInvoicesUsedThisMonth: 10,
          eInvoicesMonthlyQuota: 10, // Quota exhausted
          eWayBillsUsedThisMonth: 5,
          eWayBillsMonthlyQuota: 5, // Quota exhausted
        ),
      );

      final now = DateTime(2026, 9, 23);
      final voucher = VoucherModel(
        id: 'vch_quota',
        companyId: 'cmp_default',
        voucherNumber: 'INV-QUOTA-01',
        type: VoucherType.sales,
        date: now,
        totalAmountInCents: 100000,
        createdAt: now,
        updatedAt: now,
      );

      final einvResult = await exhaustedService.generateEInvoice(
        voucher: voucher,
        supplierGstin: '29ABCDE1234F1ZH',
        buyerGstin: '29XYZDE9876K1Z2',
        overrideNow: now,
      );
      expect(einvResult.success, isFalse);
      expect(einvResult.errorMessage, contains('Subscription Quota Exceeded'));

      final ewbResult = await exhaustedService.generateEWayBill(
        voucher: voucher,
        supplierGstin: '29ABCDE1234F1ZH',
        isBillToShipToDifferent: false,
        shipToGstinOrUrp: null,
        overrideNow: now,
      );
      expect(ewbResult.success, isFalse);
      expect(ewbResult.errorMessage, contains('Subscription Quota Exceeded'));
    });
  });
}
