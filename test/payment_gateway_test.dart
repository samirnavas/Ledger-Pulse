import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/payment_gateway_service.dart';

void main() {
  group('Payment Gateways & UPI Drop-in Tests (FR-PMT-01)', () {
    late Company testCompany;
    late Party testParty;
    late VoucherModel testInvoice;

    setUp(() {
      testCompany = Company(
        id: 'cmp_pay_01',
        name: 'Prime Retail Innovations',
        legalName: 'Prime Retail Innovations Pvt Ltd',
        bankAccountNumber: '987654321012',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      testParty = Party(
        id: 'pty_cust_01',
        name: 'Apex Infotech Solutions',
        phoneNumber: '+91 98765 43210',
        type: PartyType.customer,
        netBalanceInCents: 1500000,
        lastUpdated: DateTime.now(),
      );

      testInvoice = VoucherModel(
        id: 'vch_inv_998',
        companyId: testCompany.id,
        voucherNumber: 'INV-2026-0099',
        type: VoucherType.sales,
        date: DateTime.now(),
        partyId: testParty.id,
        partyName: testParty.name,
        totalAmountInCents: 1500000, // ₹15,000
        status: VoucherStatus.posted,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test('generateUpiUri outputs valid standard UPI intent URI', () {
      final upiUri = PaymentGatewayService.generateUpiUri(
        payeeVpa: 'prime.retail@icici',
        payeeName: 'Prime Retail Innovations',
        amountInCents: 1500000,
        invoiceNumber: 'INV-2026-0099',
      );

      expect(upiUri, startsWith('upi://pay?'));
      expect(upiUri, contains('pa=prime.retail@icici'));
      expect(upiUri, contains('am=15000.00'));
      expect(upiUri, contains('cu=INR'));
    });

    test('createInvoicePaymentLink generates hosted links for Razorpay and Paytm', () {
      final rzpPayload = PaymentGatewayService.createInvoicePaymentLink(
        voucher: testInvoice,
        company: testCompany,
        party: testParty,
        provider: PaymentGatewayProvider.razorpay,
      );

      expect(rzpPayload.paymentUrl, startsWith('https://rzp.io/l/'));
      expect(rzpPayload.upiIntentUri, startsWith('upi://pay?'));
      expect(rzpPayload.amountInCents, equals(1500000));

      final paytmPayload = PaymentGatewayService.createInvoicePaymentLink(
        voucher: testInvoice,
        company: testCompany,
        party: testParty,
        provider: PaymentGatewayProvider.paytm,
      );

      expect(paytmPayload.paymentUrl, startsWith('https://paytm.me/'));
    });

    test('handlePaymentSuccessCallback produces auto-posted Receipt Voucher', () {
      final callback = PaymentGatewayService.handlePaymentSuccessCallback(
        company: testCompany,
        invoiceVoucher: testInvoice,
        gatewayTransactionId: 'pay_rzp_9918239123',
        paymentMode: 'UPI / NetBanking',
      );

      expect(callback.isSuccess, isTrue);
      expect(callback.transactionId, equals('pay_rzp_9918239123'));
      expect(callback.generatedReceiptVoucher, isNotNull);

      final receipt = callback.generatedReceiptVoucher!;
      expect(receipt.type, equals(VoucherType.receipt));
      expect(receipt.totalAmountInCents, equals(1500000));
      expect(receipt.sourceVoucherId, equals(testInvoice.id));
      expect(receipt.paymentMode, equals(PaymentMode.upi));
      expect(receipt.narration, contains('pay_rzp_9918239123'));
    });
  });
}
