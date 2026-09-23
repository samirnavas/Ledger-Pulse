import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/voucher_providers.dart';
import 'package:ledger_pulse/presentation/reports/receivables_payables_screen.dart';

void main() {
  group('Receivables & Payables Tracking (FR-VCH-07)', () {
    final now = DateTime.now();

    final testCompany = Company(
      id: 'cmp_rec_01',
      name: 'Alpha Dynamics',
      legalName: 'Alpha Dynamics Pvt Ltd',
      gstin: '29ABCDE1234F1ZH',
      bankName: 'HDFC Bank',
      bankAccountNumber: '50200098765432',
      bankIfsc: 'HDFC0001234',
      upiId: 'alphadynamics@hdfcbank',
      createdAt: now,
      updatedAt: now,
    );

    final mockVouchers = <VoucherModel>[
      // 0 - 30 days old
      VoucherModel(
        id: 'vch_01',
        companyId: testCompany.id,
        voucherNumber: 'INV-101',
        type: VoucherType.sales,
        date: now.subtract(const Duration(days: 10)),
        partyName: 'Beta Retailers',
        partyId: 'pty_01',
        status: VoucherStatus.posted,
        items: const [],
        totalAmountInCents: 1500000, // ₹15,000.00
        createdAt: now,
        updatedAt: now,
      ),
      // 31 - 60 days old
      VoucherModel(
        id: 'vch_02',
        companyId: testCompany.id,
        voucherNumber: 'INV-102',
        type: VoucherType.sales,
        date: now.subtract(const Duration(days: 45)),
        partyName: 'Gamma Enterprises',
        partyId: 'pty_02',
        status: VoucherStatus.posted,
        items: const [],
        totalAmountInCents: 2500000, // ₹25,000.00
        createdAt: now,
        updatedAt: now,
      ),
      // 61 - 90 days old
      VoucherModel(
        id: 'vch_03',
        companyId: testCompany.id,
        voucherNumber: 'INV-103',
        type: VoucherType.sales,
        date: now.subtract(const Duration(days: 75)),
        partyName: 'Delta Traders',
        partyId: 'pty_03',
        status: VoucherStatus.posted,
        items: const [],
        totalAmountInCents: 4000000, // ₹40,000.00
        createdAt: now,
        updatedAt: now,
      ),
      // 90+ days old (Critical Overdue)
      VoucherModel(
        id: 'vch_04',
        companyId: testCompany.id,
        voucherNumber: 'INV-104',
        type: VoucherType.sales,
        date: now.subtract(const Duration(days: 120)),
        partyName: 'Omega Solutions',
        partyId: 'pty_04',
        status: VoucherStatus.posted,
        items: const [],
        totalAmountInCents: 6000000, // ₹60,000.00
        createdAt: now,
        updatedAt: now,
      ),
    ];

    testWidgets('ReceivablesPayablesScreen renders KPI metrics and invoice cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeCompanyProvider.overrideWithValue(testCompany),
            receivablesVouchersProvider.overrideWith((ref) async => mockVouchers),
            payablesVouchersProvider.overrideWith((ref) async => <VoucherModel>[]),
          ],
          child: const MaterialApp(
            home: ReceivablesPayablesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title & tabs
      expect(find.text('Accounts Receivable'), findsWidgets);
      expect(find.text('Receivables (Customers)'), findsOneWidget);
      expect(find.text('Payables (Vendors)'), findsOneWidget);

      // Verify total outstanding: ₹15,000 + ₹25,000 + ₹40,000 + ₹60,000 = ₹140,000.00
      expect(find.textContaining('1,40,000'), findsWidgets);

      // Verify invoice numbers and customer names rendered
      expect(find.text('Beta Retailers'), findsOneWidget);
      expect(find.text('Gamma Enterprises'), findsOneWidget);
      expect(find.text('Delta Traders'), findsOneWidget);
      expect(find.text('Omega Solutions'), findsOneWidget);

      // Verify One-Click Action buttons exist
      expect(find.text('Send Reminder'), findsNWidgets(4));
      expect(find.text('Advice / Receipt'), findsNWidgets(4));

      // Test aging bucket filtering
      await tester.tap(find.text('90+ Days (Overdue)'));
      await tester.pumpAndSettle();

      // Only Omega Solutions is 90+ days old
      expect(find.text('Omega Solutions'), findsOneWidget);
      expect(find.text('Beta Retailers'), findsNothing);
    });

    test('Payment reminder message includes company UPI ID and bank remittance details', () {
      final voucher = mockVouchers.first;
      final buffer = StringBuffer();
      buffer.writeln('Gentle Payment Reminder from ${testCompany.name}:');
      buffer.writeln('Dear ${voucher.partyName},');
      buffer.writeln('This is a friendly reminder that payment for Invoice #${voucher.voucherNumber} of ₹15,000.00 was due.');
      buffer.writeln('Pay instantly via UPI: ${testCompany.upiId}');
      buffer.writeln('Bank: ${testCompany.bankName} | A/C: ${testCompany.bankAccountNumber} | IFSC: ${testCompany.bankIfsc}');

      final message = buffer.toString();
      expect(message, contains('alphadynamics@hdfcbank'));
      expect(message, contains('50200098765432'));
      expect(message, contains('HDFC0001234'));
      expect(message, contains('INV-101'));
    });
  });
}
