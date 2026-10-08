import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/voucher_model.dart';
import '../providers/voucher_providers.dart';

class OrderConversionDialog extends ConsumerWidget {
  final VoucherModel order;

  const OrderConversionDialog({super.key, required this.order});

  static Future<void> show(BuildContext context, VoucherModel order) {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => OrderConversionDialog(order: order),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => OrderConversionDialog(order: order),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final totalFormatted = CurrencyFormatter.format(order.totalAmountInCents);
    final isEstimate = order.type == VoucherType.estimate;

    final title = isEstimate ? 'Convert Quotation' : 'Convert Sales Order';

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isIos
                      ? (isEstimate ? CupertinoIcons.quote_bubble_fill : CupertinoIcons.checkmark_seal_fill)
                      : (isEstimate ? Icons.format_quote_rounded : Icons.assignment_turned_in_rounded),
                  color: isEstimate ? Colors.deepPurple : AppColors.primaryBlue,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: isIos ? -0.4 : 0,
                    color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isEstimate ? Colors.deepPurple : AppColors.primaryBlue).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.type.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isEstimate ? Colors.deepPurple : AppColors.primaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Document #${order.voucherNumber} • Party: ${order.partyName ?? "Customer"}',
          style: TextStyle(
            fontSize: 13,
            color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Text(
          'Line Items (${order.items.length}):',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        ...order.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${item.itemName} (${item.quantity.toStringAsFixed(0)} ${item.unit})',
                      style: TextStyle(
                        fontSize: 13,
                        color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(item.totalInCents),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Value:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Text(
              totalFormatted,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.receivableGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (isEstimate) ...[
          // Estimate allows converting to either Sales Order or Sales Invoice
          Row(
            children: [
              Expanded(
                child: AdaptiveButton(
                  type: AdaptiveButtonType.secondary,
                  height: 44,
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    Navigator.pop(context);
                    try {
                      final so = await ref.read(voucherControllerProvider.notifier).convertEstimateToSalesOrder(order.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Generated Sales Order #${so.voucherNumber} from ${order.voucherNumber}!'),
                            backgroundColor: AppColors.primaryBlue,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Conversion failed: $e'), backgroundColor: AppColors.payableRed),
                        );
                      }
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.doc_plaintext : Icons.assignment_rounded,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text('To Order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AdaptiveButton(
                  type: AdaptiveButtonType.primary,
                  height: 44,
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    Navigator.pop(context);
                    try {
                      final inv = await ref.read(voucherControllerProvider.notifier).convertEstimateToSalesInvoice(order.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Generated & Posted Invoice #${inv.voucherNumber} from ${order.voucherNumber}!'),
                            backgroundColor: AppColors.receivableGreen,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Conversion failed: $e'), backgroundColor: AppColors.payableRed),
                        );
                      }
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.doc_text_fill : Icons.receipt_long_rounded,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      const Text('To Invoice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ] else ...[
          // Sales Order converts to Sales Invoice
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              AdaptiveButton(
                type: AdaptiveButtonType.primary,
                height: 44,
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  try {
                    final inv = await ref.read(voucherControllerProvider.notifier).convertSalesOrderToSalesInvoice(order.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sales Order #${order.voucherNumber} converted to Sales Invoice #${inv.voucherNumber}!'),
                          backgroundColor: AppColors.receivableGreen,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Conversion failed: $e'), backgroundColor: AppColors.payableRed),
                      );
                    }
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.doc_text_fill : Icons.receipt_long_rounded,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    const Text('Convert & Post Invoice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (isIos) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return LiquidGlassCard(
        borderRadius: 24,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        padding: const EdgeInsets.all(22),
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.75) : CupertinoColors.systemBackground.withValues(alpha: 0.8),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.08),
        child: Material(
          type: MaterialType.transparency,
          child: content,
        ),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      content: content,
    );
  }
}
