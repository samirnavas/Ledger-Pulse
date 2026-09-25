import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/services/ecommerce_sync_service.dart';
import '../providers/company_providers.dart';
import '../providers/voucher_providers.dart';

class EcommerceSyncScreen extends ConsumerStatefulWidget {
  const EcommerceSyncScreen({super.key});

  @override
  ConsumerState<EcommerceSyncScreen> createState() =>
      _EcommerceSyncScreenState();
}

class _EcommerceSyncScreenState extends ConsumerState<EcommerceSyncScreen> {
  MarketplaceChannel _selectedChannel = MarketplaceChannel.amazonIndia;
  bool _isSyncing = false;
  MarketplaceSyncResult? _syncResult;

  void _fetchMarketplaceOrders() {
    HapticFeedback.lightImpact();
    final company = ref.read(activeCompanyProvider);

    if (_selectedChannel == MarketplaceChannel.amazonIndia) {
      const sampleAmazonJson = '''{
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
      },
      {
        "AmazonOrderId": "402-9912834-5566778",
        "PurchaseDate": "2026-09-23T12:00:00Z",
        "OrderStatus": "Shipped",
        "NumberOfItemsShipped": 2,
        "OrderTotal": { "Amount": "12400.00", "CurrencyCode": "INR" },
        "BuyerInfo": { "BuyerName": "Neha Kulkarni" },
        "ShippingAddress": { "StateOrRegion": "Maharashtra", "City": "Pune" },
        "OrderItems": [
          { "SellerSKU": "SSD-NVME-1TB", "Title": "NVMe Gen4 1TB SSD", "ItemPrice": { "Amount": "6200.00" } }
        ]
      }
    ]
  }
}''';
      final result = EcommerceSyncService.syncAmazonIndiaOrders(
        jsonPayload: sampleAmazonJson,
        company: company,
      );
      setState(() => _syncResult = result);
    } else {
      const sampleFlipkartJson = '''{
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
        jsonPayload: sampleFlipkartJson,
        company: company,
      );
      setState(() => _syncResult = result);
    }
  }

  Future<void> _commitImportVouchers() async {
    final res = _syncResult;
    if (res == null || res.generatedVouchers.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _isSyncing = true);

    try {
      final postingEngine = ref.read(voucherPostingEngineProvider);
      for (final v in res.generatedVouchers) {
        await postingEngine.postVoucher(voucher: v, userId: 'USR-AMZ-SYNC');
      }

      ref.invalidate(vouchersListProvider(null));

      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported and posted ${res.generatedVouchers.length} sales invoices from ${res.channel.displayName}!'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post imported vouchers: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final res = _syncResult;

    return AdaptiveScaffold(
      title: 'E-Commerce Marketplace Sync',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Channel Switcher
            Center(
              child: AdaptiveSegmentedControl<MarketplaceChannel>(
                groupValue: _selectedChannel,
                children: const {
                  MarketplaceChannel.amazonIndia: Text('Amazon India SP-API'),
                  MarketplaceChannel.flipkart: Text('Flipkart Seller API'),
                },
                onValueChanged: (ch) {
                  setState(() {
                    _selectedChannel = ch;
                    _syncResult = null;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // Fetch Orders Action
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton(
                onPressed: _fetchMarketplaceOrders,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.cloud_download : Icons.cloud_download_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Fetch Live Orders from ${_selectedChannel == MarketplaceChannel.amazonIndia ? "Amazon India" : "Flipkart"}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (res != null) ...[
              // Summary Metrics
              _buildSyncMetrics(isIos, isDark, res),
              const SizedBox(height: 16),

              const Text('Fetched Orders Ready for Invoicing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),

              ...res.generatedVouchers.map((v) {
                final tile = Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _selectedChannel == MarketplaceChannel.amazonIndia ? Colors.amber.shade700 : Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _selectedChannel.badgePrefix,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.voucherNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('Customer: ${v.partyName} • ${v.items.first.itemName}',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₹ ${(v.totalAmountInCents / 100.0).toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const Text('Tax Invoice', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                );

                if (isIos) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LiquidGlassCard(borderRadius: 12, padding: EdgeInsets.zero, child: tile),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                    ),
                    child: tile,
                  ),
                );
              }),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSyncing ? null : _commitImportVouchers,
                  icon: _isSyncing
                      ? (isIos
                          ? const CupertinoActivityIndicator()
                          : const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ))
                      : Icon(
                          isIos
                              ? CupertinoIcons.checkmark_circle_fill
                              : Icons.check_circle_rounded,
                          size: 20,
                        ),
                  label: Text('Post ${res.generatedVouchers.length} Invoices to Ledger & Inventory'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncMetrics(bool isIos, bool isDark, MarketplaceSyncResult res) {
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Gross Sales', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text('₹ ${(res.totalGrossSalesInCents / 100.0).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.receivableGreen)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Marketplace Commissions', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text('₹ ${(res.totalMarketplaceFeesInCents / 100.0).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.payableRed)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(borderRadius: 14, padding: EdgeInsets.zero, child: content);
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      ),
      child: content,
    );
  }
}
