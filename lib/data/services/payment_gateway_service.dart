import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/company_model.dart';
import '../models/party_model.dart';
import '../models/voucher_model.dart';

enum PaymentGatewayProvider {
  bharatUpi,
  razorpay,
  paytm,
  cashfree,
  stripe;

  String get displayName {
    switch (this) {
      case PaymentGatewayProvider.bharatUpi:
        return 'Bharat UPI (GPay / PhonePe / Paytm)';
      case PaymentGatewayProvider.razorpay:
        return 'Razorpay Payment Gateway';
      case PaymentGatewayProvider.paytm:
        return 'Paytm All-In-One Gateway';
      case PaymentGatewayProvider.cashfree:
        return 'Cashfree Payments';
      case PaymentGatewayProvider.stripe:
        return 'Stripe Payments (Global / INR)';
    }
  }
}

class PaymentLinkPayload {
  final PaymentGatewayProvider provider;
  final String paymentUrl;
  final String upiIntentUri;
  final String paymentReferenceId;
  final int amountInCents;
  final String currency;
  final String customerName;
  final String? customerPhone;

  const PaymentLinkPayload({
    required this.provider,
    required this.paymentUrl,
    required this.upiIntentUri,
    required this.paymentReferenceId,
    required this.amountInCents,
    this.currency = 'INR',
    required this.customerName,
    this.customerPhone,
  });
}

class PaymentCallbackResult {
  final bool isSuccess;
  final String transactionId;
  final String paymentMode;
  final int amountInCents;
  final DateTime paidAt;
  final VoucherModel? generatedReceiptVoucher;

  const PaymentCallbackResult({
    required this.isSuccess,
    required this.transactionId,
    required this.paymentMode,
    required this.amountInCents,
    required this.paidAt,
    this.generatedReceiptVoucher,
  });
}

class PaymentGatewayService {
  /// Generates a Bharat UPI dynamic payment string standard
  static String generateUpiUri({
    required String payeeVpa,
    required String payeeName,
    required int amountInCents,
    required String invoiceNumber,
  }) {
    final amountInRupees = (amountInCents / 100.0).toStringAsFixed(2);
    final note = 'Payment for Invoice $invoiceNumber';
    return 'upi://pay?pa=$payeeVpa&pn=${Uri.encodeComponent(payeeName)}&am=$amountInRupees&cu=INR&tn=${Uri.encodeComponent(note)}';
  }

  /// Creates a unified online payment link for an invoice
  static PaymentLinkPayload createInvoicePaymentLink({
    required VoucherModel voucher,
    required Company company,
    required Party party,
    PaymentGatewayProvider provider = PaymentGatewayProvider.razorpay,
  }) {
    final invoiceNo = voucher.voucherNumber;
    final amountInCents = voucher.totalAmountInCents;
    final payeeVpa = company.bankAccountNumber != null
        ? '${company.bankAccountNumber}@upi'
        : 'ludgerpulse.${company.id}@icici';

    final upiUri = generateUpiUri(
      payeeVpa: payeeVpa,
      payeeName: company.name,
      amountInCents: amountInCents,
      invoiceNumber: invoiceNo,
    );

    final rawRef = '${company.id}:$invoiceNo:${DateTime.now().millisecondsSinceEpoch}';
    final refId = 'PL_${sha256.convert(utf8.encode(rawRef)).toString().substring(0, 12).toUpperCase()}';

    String hostedUrl;
    switch (provider) {
      case PaymentGatewayProvider.razorpay:
        hostedUrl = 'https://rzp.io/l/$refId';
        break;
      case PaymentGatewayProvider.paytm:
        hostedUrl = 'https://paytm.me/$refId';
        break;
      case PaymentGatewayProvider.cashfree:
        hostedUrl = 'https://cashfree.com/pay/$refId';
        break;
      case PaymentGatewayProvider.stripe:
        hostedUrl = 'https://buy.stripe.com/$refId';
        break;
      case PaymentGatewayProvider.bharatUpi:
        hostedUrl = upiUri;
        break;
    }

    return PaymentLinkPayload(
      provider: provider,
      paymentUrl: hostedUrl,
      upiIntentUri: upiUri,
      paymentReferenceId: refId,
      amountInCents: amountInCents,
      customerName: party.name,
      customerPhone: party.phoneNumber,
    );
  }

  /// Simulates / processes a webhook payment success callback and constructs a double-entry Receipt Voucher
  static PaymentCallbackResult handlePaymentSuccessCallback({
    required Company company,
    required VoucherModel invoiceVoucher,
    required String gatewayTransactionId,
    required String paymentMode,
  }) {
    final now = DateTime.now();
    final receiptVoucherNumber = 'RCP-${invoiceVoucher.voucherNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}';

    final receiptVoucher = VoucherModel(
      id: 'vch_rcp_${now.millisecondsSinceEpoch}',
      companyId: company.id,
      voucherNumber: receiptVoucherNumber,
      type: VoucherType.receipt,
      date: now,
      partyId: invoiceVoucher.partyId,
      partyName: invoiceVoucher.partyName,
      status: VoucherStatus.posted,
      paymentMode: PaymentMode.upi,
      subtotalInCents: invoiceVoucher.totalAmountInCents,
      taxInCents: 0,
      discountInCents: 0,
      totalAmountInCents: invoiceVoucher.totalAmountInCents,
      narration: 'Online Payment received via $paymentMode (Txn ID: $gatewayTransactionId) against Invoice #${invoiceVoucher.voucherNumber}.',
      referenceNumber: gatewayTransactionId,
      sourceVoucherId: invoiceVoucher.id,
      createdAt: now,
      updatedAt: now,
    );

    return PaymentCallbackResult(
      isSuccess: true,
      transactionId: gatewayTransactionId,
      paymentMode: paymentMode,
      amountInCents: invoiceVoucher.totalAmountInCents,
      paidAt: now,
      generatedReceiptVoucher: receiptVoucher,
    );
  }
}
