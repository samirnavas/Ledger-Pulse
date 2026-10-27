import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/adaptive_button.dart';
import '../../../core/widgets/liquid_glass_card.dart';
import '../../../data/models/voucher_model.dart';
import 'voucher_adaptive_card.dart';
import 'voucher_form_controller.dart';
import 'voucher_item_selector_modal.dart';

/// Line items editor section of VoucherCreationScreen for stock inventory and service items.
class VoucherLineItemsSection extends StatelessWidget {
  final VoucherFormController controller;

  const VoucherLineItemsSection({
    super.key,
    required this.controller,
  });

  void _showAddItemSelectorSheet(BuildContext context, {bool startWithService = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoucherItemSelectorModal(
        voucherType: controller.selectedType,
        initialIsService: startWithService,
        onItemAdded: controller.addItem,
      ),
    );
  }

  void _showEditItemQty(BuildContext context, int index) {
    final item = controller.items[index];
    final qtyController = TextEditingController(text: item.quantity.toStringAsFixed(0));
    final rateController =
        TextEditingController(text: (item.unitPriceInCents / 100.0).toStringAsFixed(2));
    final isIos = AdaptiveThemeHelper.isIos(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Edit ${item.itemName}',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: qtyController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity (${item.unit})',
            prefixIcon: Icon(isIos ? CupertinoIcons.number : Icons.tag_rounded, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: rateController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Unit Rate (₹)',
            prefixIcon: Icon(isIos ? CupertinoIcons.money_dollar : Icons.currency_rupee_rounded, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            AdaptiveButton(
              type: AdaptiveButtonType.primary,
              height: 40,
              onPressed: () {
                final newQty = double.tryParse(qtyController.text) ?? item.quantity;
                final newRate =
                    double.tryParse(rateController.text) ?? (item.unitPriceInCents / 100.0);
                final unitPriceCents = (newRate * 100).round();
                final grossCents = (unitPriceCents * newQty).round();
                final taxCents = ((grossCents * item.taxRatePercent) / 100.0).round();

                controller.updateItem(
                  index,
                  VoucherItemModel(
                    itemId: item.itemId,
                    itemName: item.itemName,
                    sku: item.sku,
                    hsnCode: item.hsnCode,
                    quantity: newQty,
                    unit: item.unit,
                    unitPriceInCents: unitPriceCents,
                    taxRatePercent: item.taxRatePercent,
                    discountInCents: item.discountInCents,
                    cgstInCents: item.cgstInCents,
                    sgstInCents: item.sgstInCents,
                    igstInCents: item.igstInCents,
                    totalInCents: grossCents + taxCents,
                  ),
                );
                Navigator.pop(context);
              },
              child: const Text('Update Item'),
            ),
          ],
        ),
      ],
    );

    if (isIos) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => LiquidGlassCard(
          borderRadius: 24,
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          padding: const EdgeInsets.all(20),
          color: isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.8)
              : CupertinoColors.systemBackground.withValues(alpha: 0.85),
          child: Material(
            type: MaterialType.transparency,
            child: content,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          content: content,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final accentColor = controller.getTypeAccentColor();
    final items = controller.items;

    return VoucherAdaptiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Line Items (${items.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Wrap(
                spacing: 2,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _showAddItemSelectorSheet(context, startWithService: false),
                    icon: Icon(
                      isIos ? CupertinoIcons.cube_box : Icons.inventory_2_outlined,
                      size: 15,
                      color: accentColor,
                    ),
                    label: Text(
                      '+ Stock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _showAddItemSelectorSheet(context, startWithService: true),
                    icon: Icon(
                      isIos ? CupertinoIcons.bolt : Icons.miscellaneous_services_outlined,
                      size: 15,
                      color: Colors.deepPurple,
                    ),
                    label: const Text(
                      '+ Service',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 1),
          if (items.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.cart_badge_plus : Icons.add_shopping_cart_rounded,
                      size: 38,
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No line items added yet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.isPurchase
                          ? 'Select inventory goods from Item Master or add service lines.'
                          : 'Select goods from Item Master inventory or add non-stock service lines.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () =>
                              _showAddItemSelectorSheet(context, startWithService: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          icon: const Icon(Icons.inventory_2_rounded, size: 16),
                          label: const Text(
                            'Add from Item Master',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _showAddItemSelectorSheet(context, startWithService: true),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: const Icon(Icons.flash_on_rounded, size: 16, color: Colors.deepPurple),
                          label: const Text(
                            'Add Service Line',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            ...List.generate(items.length, (index) {
              final item = items[index];
              final isService = item.itemId.startsWith('srv_');
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isService
                                ? Colors.deepPurple.withValues(alpha: 0.12)
                                : accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isService ? '⚡ Service' : '📦 Stock (${item.unit})',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isService ? Colors.deepPurple : accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.itemName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(item.totalInCents),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'HSN: ${item.hsnCode} • ₹${(item.unitPriceInCents / 100.0).toStringAsFixed(2)} • GST ${item.taxRatePercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Row(
                          children: [
                            // Quantity Stepper Controls
                            InkWell(
                              onTap: () {
                                if (item.quantity > 1) {
                                  final newQty = item.quantity - 1;
                                  final unitPrice = item.unitPriceInCents;
                                  final gross = (unitPrice * newQty).round();
                                  final tax = ((gross * item.taxRatePercent) / 100.0).round();
                                  controller.updateItem(
                                    index,
                                    VoucherItemModel(
                                      itemId: item.itemId,
                                      itemName: item.itemName,
                                      sku: item.sku,
                                      hsnCode: item.hsnCode,
                                      quantity: newQty,
                                      unit: item.unit,
                                      unitPriceInCents: unitPrice,
                                      taxRatePercent: item.taxRatePercent,
                                      discountInCents: item.discountInCents,
                                      cgstInCents: item.cgstInCents,
                                      sgstInCents: item.sgstInCents,
                                      igstInCents: item.igstInCents,
                                      totalInCents: gross + tax,
                                    ),
                                  );
                                } else {
                                  controller.removeItem(index);
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.remove, size: 14),
                              ),
                            ),
                            InkWell(
                              onTap: () => _showEditItemQty(context, index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                final newQty = item.quantity + 1;
                                final unitPrice = item.unitPriceInCents;
                                final gross = (unitPrice * newQty).round();
                                final tax = ((gross * item.taxRatePercent) / 100.0).round();
                                controller.updateItem(
                                  index,
                                  VoucherItemModel(
                                    itemId: item.itemId,
                                    itemName: item.itemName,
                                    sku: item.sku,
                                    hsnCode: item.hsnCode,
                                    quantity: newQty,
                                    unit: item.unit,
                                    unitPriceInCents: unitPrice,
                                    taxRatePercent: item.taxRatePercent,
                                    discountInCents: item.discountInCents,
                                    cgstInCents: item.cgstInCents,
                                    sgstInCents: item.sgstInCents,
                                    igstInCents: item.igstInCents,
                                    totalInCents: gross + tax,
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.add, size: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              onPressed: () => controller.removeItem(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
