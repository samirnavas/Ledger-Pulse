import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
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

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Convert to Sales Invoice',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.type.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Document #${order.voucherNumber} • Party: ${order.partyName ?? 'Customer'}'),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Text('Line Items (${order.items.length}):', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        ...order.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${item.itemName} (${item.quantity.toStringAsFixed(0)} ${item.unit})', style: const TextStyle(fontSize: 13)),
                  Text(CurrencyFormatter.format(item.totalInCents), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            )),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total Invoice Value:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(totalFormatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
          ],
        ),
        const SizedBox(height: 18),
        if (isIos)
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: CupertinoButton.filled(
                  child: const Text('Convert'),
                  onPressed: () async {
                    Navigator.pop(context);
                    await ref.read(voucherControllerProvider.notifier).convertToInvoice(order.id);
                  },
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Convert & Post Invoice'),
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(voucherControllerProvider.notifier).convertToInvoice(order.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${order.voucherNumber} successfully converted to Sales Invoice!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
      ],
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 24,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        padding: const EdgeInsets.all(22),
        color: CupertinoColors.systemBackground.resolveFrom(context).withValues(alpha: 0.8),
        child: Material(
          type: MaterialType.transparency,
          child: content,
        ),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: content,
    );
  }
}
