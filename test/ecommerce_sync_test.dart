import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/ecommerce_sync_service.dart';

void main() {
  group('E-Commerce Sync Service Tests (FR-SYN-05)', () {
    late Company testCompany;

    setUp(() {
      testCompany = Company(
        id: 'cmp_ecommerce_01',
        name: 'OmniRetail Online Ltd',
        legalName: 'OmniRetail Online Ltd',
        gstin: '29ABCDE1234F1ZH',
        stateCode: '29',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test('syncAmazonIndiaOrders converts Amazon SP-API payload into sales vouchers and customer parties', () {
      const amazonJson = '''{
  "payload": {
    "Orders": [
      {
        "AmazonOrderId": "402-8871923-1123456",
        "PurchaseDate": "2026-09-23T14:20:00Z",
        "OrderStatus": "Shipped",
        "NumberOfItemsShipped": 1,
        "OrderTotal": { "Amount": "4500.00", "CurrencyCode": "INR" },
        "BuyerInfo": { "BuyerName": "Aditya Verma" },
        "ShippingAddress": { "StateOrRegion": "Karnataka", "City": "Bengaluru" },
        "OrderItems": [
          { "SellerSKU": "MEM-DDR5-16", "Title": "RAM DDR5 16GB Module", "ItemPrice": { "Amount": "4500.00" } }
        ]
      }
    ]
  }
}''';

      final result = EcommerceSyncService.syncAmazonIndiaOrders(
        jsonPayload: amazonJson,
        company: testCompany,
      );

      expect(result.channel, equals(MarketplaceChannel.amazonIndia));
      expect(result.totalOrdersFetched, equals(1));
      expect(result.generatedVouchers.length, equals(1));
      expect(result.generatedCustomers.length, equals(1));

      final voucher = result.generatedVouchers.first;
      expect(voucher.voucherNumber, equals('402-8871923-1123456'));
      expect(voucher.type, equals(VoucherType.sales));
      expect(voucher.totalAmountInCents, equals(450000)); // ₹4,500
      expect(voucher.partyName, equals('Aditya Verma'));
      expect(result.totalMarketplaceFeesInCents, equals(54000)); // 12% = ₹540
    });

    test('syncFlipkartOrders converts Flipkart seller orders into sales invoices with commission tracking', () {
      const flipkartJson = '''{
  "orderItems": [
    {
      "orderId": "OD449911223344",
      "orderItemId": "OD449911223344_1",
      "orderDate": "2026-09-23T11:15:00Z",
      "status": "APPROVED",
      "quantity": 1,
      "sku": "SYS-DT-01",
      "title": "Desktop Computer Pro Core i7",
      "priceComponents": { "sellingPrice": 45000.00 },
      "deliveryAddress": { "firstName": "Ramesh Gupta", "state": "Delhi", "city": "New Delhi" }
    }
  ]
}''';

      final result = EcommerceSyncService.syncFlipkartOrders(
        jsonPayload: flipkartJson,
        company: testCompany,
      );

      expect(result.channel, equals(MarketplaceChannel.flipkart));
      expect(result.totalOrdersFetched, equals(1));
      expect(result.generatedVouchers.length, equals(1));

      final voucher = result.generatedVouchers.first;
      expect(voucher.voucherNumber, equals('FK-OD449911223344'));
      expect(voucher.totalAmountInCents, equals(4500000)); // ₹45,000
      expect(voucher.partyName, equals('Ramesh Gupta'));
      expect(result.totalMarketplaceFeesInCents, equals(450000)); // 10% = ₹4,500
    });
  });
}
