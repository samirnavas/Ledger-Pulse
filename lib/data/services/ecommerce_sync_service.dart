import 'dart:convert';
import '../models/company_model.dart';
import '../models/party_model.dart';
import '../models/voucher_model.dart';

enum MarketplaceChannel {
  amazonIndia,
  flipkart;

  String get displayName {
    switch (this) {
      case MarketplaceChannel.amazonIndia:
        return 'Amazon India (SP-API)';
      case MarketplaceChannel.flipkart:
        return 'Flipkart Seller API';
    }
  }

  String get badgePrefix {
    switch (this) {
      case MarketplaceChannel.amazonIndia:
        return 'AMZN';
      case MarketplaceChannel.flipkart:
        return 'FK';
    }
  }
}

class MarketplaceSyncResult {
  final MarketplaceChannel channel;
  final int totalOrdersFetched;
  final List<VoucherModel> generatedVouchers;
  final List<Party> generatedCustomers;
  final int totalGrossSalesInCents;
  final int totalMarketplaceFeesInCents;

  const MarketplaceSyncResult({
    required this.channel,
    required this.totalOrdersFetched,
    required this.generatedVouchers,
    required this.generatedCustomers,
    required this.totalGrossSalesInCents,
    required this.totalMarketplaceFeesInCents,
  });
}

class EcommerceSyncService {
  /// Parses Amazon India SP-API Orders Payload and generates Sales Invoices
  static MarketplaceSyncResult syncAmazonIndiaOrders({
    required String jsonPayload,
    required Company company,
  }) {
    final Map<String, dynamic> data = jsonDecode(jsonPayload);
    final List<dynamic> ordersList = data['Orders'] ?? data['payload']?['Orders'] ?? [];

    final vouchers = <VoucherModel>[];
    final customers = <Party>[];
    int totalGross = 0;
    int totalFees = 0;

    for (final order in ordersList) {
      final orderId = order['AmazonOrderId'] ?? 'AMZ-${DateTime.now().millisecondsSinceEpoch}';
      final orderTotalStr = order['OrderTotal']?['Amount'] ?? '0';
      final totalAmountInCents = ((double.tryParse(orderTotalStr.toString()) ?? 0.0) * 100).round();
      final buyerName = order['BuyerInfo']?['BuyerName'] ?? 'Amazon Customer';
      final stateName = order['ShippingAddress']?['StateOrRegion'] ?? 'Karnataka';
      final purchaseDate = DateTime.tryParse(order['PurchaseDate'] ?? '') ?? DateTime.now();

      final customer = Party(
        id: 'pty_amz_${orderId.replaceAll("-", "_")}',
        name: buyerName,
        phoneNumber: '9999999999',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: purchaseDate,
      );
      customers.add(customer);

      final feeAmountInCents = (totalAmountInCents * 0.12).round(); // ~12% Amazon Referral & EasyShip fee
      totalGross += totalAmountInCents;
      totalFees += feeAmountInCents;

      final items = <VoucherItemModel>[
        VoucherItemModel(
          itemId: 'itm_amz_${orderId.substring(0, 6)}',
          itemName: order['OrderItems']?[0]?['Title'] ?? 'Amazon Order Item: $orderId',
          sku: order['OrderItems']?[0]?['SellerSKU'] ?? 'AMZ-SKU',
          quantity: (order['NumberOfItemsShipped'] as num?)?.toDouble() ?? 1.0,
          unitPriceInCents: totalAmountInCents,
          taxRatePercent: 18.0,
          igstInCents: (totalAmountInCents * 0.18 / 1.18).round(),
          totalInCents: totalAmountInCents,
        ),
      ];

      vouchers.add(
        VoucherModel(
          id: 'vch_amz_${orderId.replaceAll("-", "_")}',
          companyId: company.id,
          voucherNumber: orderId,
          type: VoucherType.sales,
          date: purchaseDate,
          partyId: customer.id,
          partyName: customer.name,
          status: VoucherStatus.posted,
          subtotalInCents: totalAmountInCents - (totalAmountInCents * 0.18 / 1.18).round(),
          taxInCents: (totalAmountInCents * 0.18 / 1.18).round(),
          discountInCents: 0,
          totalAmountInCents: totalAmountInCents,
          narration: 'Amazon India Order #$orderId shipped to $stateName. Referral & FBA Fee: ₹${(feeAmountInCents / 100.0).toStringAsFixed(2)}',
          referenceNumber: orderId,
          items: items,
          createdAt: purchaseDate,
          updatedAt: DateTime.now(),
        ),
      );
    }

    return MarketplaceSyncResult(
      channel: MarketplaceChannel.amazonIndia,
      totalOrdersFetched: ordersList.length,
      generatedVouchers: vouchers,
      generatedCustomers: customers,
      totalGrossSalesInCents: totalGross,
      totalMarketplaceFeesInCents: totalFees,
    );
  }

  /// Parses Flipkart Seller API Orders Payload and generates Sales Invoices
  static MarketplaceSyncResult syncFlipkartOrders({
    required String jsonPayload,
    required Company company,
  }) {
    final Map<String, dynamic> data = jsonDecode(jsonPayload);
    final List<dynamic> orderItems = data['orderItems'] ?? [];

    final vouchers = <VoucherModel>[];
    final customers = <Party>[];
    int totalGross = 0;
    int totalFees = 0;

    for (final item in orderItems) {
      final orderId = item['orderId'] ?? 'OD${DateTime.now().millisecondsSinceEpoch}';
      final orderItemId = item['orderItemId'] ?? orderId;
      final price = (item['priceComponents']?['sellingPrice'] as num?)?.toDouble() ?? 0.0;
      final totalAmountInCents = (price * 100).round();
      final customerName = item['deliveryAddress']?['firstName'] ?? 'Flipkart Customer';
      final state = item['deliveryAddress']?['state'] ?? 'Maharashtra';
      final orderDate = DateTime.tryParse(item['orderDate'] ?? '') ?? DateTime.now();

      final customer = Party(
        id: 'pty_fk_${orderItemId.replaceAll("-", "_")}',
        name: customerName,
        phoneNumber: '9999999999',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: orderDate,
      );
      customers.add(customer);

      final feeAmountInCents = (totalAmountInCents * 0.10).round(); // ~10% Flipkart Commission
      totalGross += totalAmountInCents;
      totalFees += feeAmountInCents;

      final voucherItems = <VoucherItemModel>[
        VoucherItemModel(
          itemId: 'itm_fk_$orderItemId',
          itemName: item['title'] ?? 'Flipkart Product SKU',
          sku: item['sku'] ?? 'FK-SKU',
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1.0,
          unitPriceInCents: totalAmountInCents,
          taxRatePercent: 18.0,
          igstInCents: (totalAmountInCents * 0.18 / 1.18).round(),
          totalInCents: totalAmountInCents,
        ),
      ];

      vouchers.add(
        VoucherModel(
          id: 'vch_fk_${orderItemId.replaceAll("-", "_")}',
          companyId: company.id,
          voucherNumber: 'FK-$orderId',
          type: VoucherType.sales,
          date: orderDate,
          partyId: customer.id,
          partyName: customer.name,
          status: VoucherStatus.posted,
          subtotalInCents: totalAmountInCents - (totalAmountInCents * 0.18 / 1.18).round(),
          taxInCents: (totalAmountInCents * 0.18 / 1.18).round(),
          discountInCents: 0,
          totalAmountInCents: totalAmountInCents,
          narration: 'Flipkart Order #$orderId (Item: $orderItemId) delivered to $state. Marketplace Fee: ₹${(feeAmountInCents / 100.0).toStringAsFixed(2)}',
          referenceNumber: orderId,
          items: voucherItems,
          createdAt: orderDate,
          updatedAt: DateTime.now(),
        ),
      );
    }

    return MarketplaceSyncResult(
      channel: MarketplaceChannel.flipkart,
      totalOrdersFetched: orderItems.length,
      generatedVouchers: vouchers,
      generatedCustomers: customers,
      totalGrossSalesInCents: totalGross,
      totalMarketplaceFeesInCents: totalFees,
    );
  }
}
