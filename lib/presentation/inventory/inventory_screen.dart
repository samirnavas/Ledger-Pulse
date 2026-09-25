import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/inventory_item_model.dart';
import '../../data/models/stock_ledger_model.dart';
import '../providers/inventory_providers.dart';
import '../providers/sync_providers.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  void _showAddEditItemDialog(BuildContext context, [InventoryItem? itemToEdit]) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final skuCtrl = TextEditingController(text: itemToEdit?.sku ?? 'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
    final nameCtrl = TextEditingController(text: itemToEdit?.name ?? '');
    final unitCtrl = TextEditingController(text: itemToEdit?.unit ?? 'PCS');
    final buyPriceCtrl = TextEditingController(text: itemToEdit != null ? (itemToEdit.purchasePriceInCents / 100).toStringAsFixed(2) : '0');
    final sellPriceCtrl = TextEditingController(text: itemToEdit != null ? (itemToEdit.sellingPriceInCents / 100).toStringAsFixed(2) : '0');
    final stockCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.currentStockQuantity.toString() : '0');
    final alertCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.minimumStockAlert.toString() : '5');

    void onSave() {
      if (nameCtrl.text.trim().isEmpty) return;
      final buyCents = ((double.tryParse(buyPriceCtrl.text) ?? 0) * 100).round();
      final sellCents = ((double.tryParse(sellPriceCtrl.text) ?? 0) * 100).round();
      final stockQty = double.tryParse(stockCtrl.text) ?? 0.0;
      final minAlert = double.tryParse(alertCtrl.text) ?? 5.0;

      if (itemToEdit == null) {
        final newItem = InventoryItem(
          id: 'item_${DateTime.now().millisecondsSinceEpoch}',
          companyId: 'cmp_default',
          sku: skuCtrl.text.trim(),
          name: nameCtrl.text.trim(),
          unit: unitCtrl.text.trim().toUpperCase(),
          purchasePriceInCents: buyCents,
          sellingPriceInCents: sellCents,
          currentStockQuantity: stockQty,
          minimumStockAlert: minAlert,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        ref.read(inventoryControllerProvider.notifier).addItem(newItem);
      } else {
        final updated = itemToEdit.copyWith(
          sku: skuCtrl.text.trim(),
          name: nameCtrl.text.trim(),
          unit: unitCtrl.text.trim().toUpperCase(),
          purchasePriceInCents: buyCents,
          sellingPriceInCents: sellCents,
          minimumStockAlert: minAlert,
          updatedAt: DateTime.now(),
        );
        ref.read(inventoryControllerProvider.notifier).updateItem(updated);
      }
      Navigator.pop(context);
    }

    if (isIos) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(itemToEdit == null ? 'New Inventory Item' : 'Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                CupertinoTextField(controller: skuCtrl, placeholder: 'SKU Code'),
                const SizedBox(height: 8),
                CupertinoTextField(controller: nameCtrl, placeholder: 'Item / Product Name'),
                const SizedBox(height: 8),
                CupertinoTextField(controller: unitCtrl, placeholder: 'Unit (PCS, KG, BOX)'),
                const SizedBox(height: 8),
                CupertinoTextField(controller: buyPriceCtrl, placeholder: 'Purchase Price (₹)', keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                CupertinoTextField(controller: sellPriceCtrl, placeholder: 'Selling Price (₹)', keyboardType: TextInputType.number),
                if (itemToEdit == null) ...[
                  const SizedBox(height: 8),
                  CupertinoTextField(controller: stockCtrl, placeholder: 'Opening Stock Qty', keyboardType: TextInputType.number),
                ],
                const SizedBox(height: 8),
                CupertinoTextField(controller: alertCtrl, placeholder: 'Low Stock Alert Qty', keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
            CupertinoDialogAction(isDefaultAction: true, onPressed: onSave, child: const Text('Save Item')),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(itemToEdit == null ? 'Add Inventory SKU' : 'Edit SKU'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU Code *', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Item Name *', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Unit (e.g. PCS, KG)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: buyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Buy Price (₹)', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: sellPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sell Price (₹)', border: OutlineInputBorder()))),
                  ],
                ),
                if (itemToEdit == null) ...[
                  const SizedBox(height: 10),
                  TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Initial Stock Qty', border: OutlineInputBorder())),
                ],
                const SizedBox(height: 10),
                TextField(controller: alertCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Alert Level', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
            FilledButton(onPressed: onSave, child: const Text('Save Item')),
          ],
        ),
      );
    }
  }

  void _showAdjustStockDialog(BuildContext context, InventoryItem item) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController(text: 'Physical inventory audit');
    StockTransactionType type = StockTransactionType.adjustment;

    if (isIos) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('Adjust Stock: ${item.name}'),
          content: Column(
            children: [
              const SizedBox(height: 10),
              Text('Current Stock: ${item.currentStockQuantity} ${item.unit}'),
              const SizedBox(height: 10),
              CupertinoTextField(controller: qtyCtrl, placeholder: 'Adjustment Quantity (+/-)', keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              CupertinoTextField(controller: noteCtrl, placeholder: 'Adjustment Reason'),
            ],
          ),
          actions: [
            CupertinoDialogAction(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Apply'),
              onPressed: () {
                final delta = double.tryParse(qtyCtrl.text) ?? 0.0;
                ref.read(inventoryControllerProvider.notifier).adjustStock(
                      itemId: item.id,
                      quantityDelta: delta,
                      type: type,
                      note: noteCtrl.text.trim(),
                    );
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Adjust Stock: ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current on hand: ${item.currentStockQuantity} ${item.unit}'),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity Change (e.g. +5 or -2)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Reason / Note', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
            FilledButton(
              child: const Text('Confirm Adjustment'),
              onPressed: () {
                final delta = double.tryParse(qtyCtrl.text) ?? 0.0;
                ref.read(inventoryControllerProvider.notifier).adjustStock(
                      itemId: item.id,
                      quantityDelta: delta,
                      type: type,
                      note: noteCtrl.text.trim(),
                    );
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final itemsAsync = ref.watch(inventoryItemsListProvider);
    final valuationAsync = ref.watch(inventoryValuationProvider);
    final isLowStockOnly = ref.watch(inventoryLowStockFilterProvider);

    return AdaptiveScaffold(
      title: 'Item Master & Inventory',
      actions: [
        if (isIos)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _showAddEditItemDialog(context),
            child: const Icon(CupertinoIcons.plus_circle_fill, size: 26),
          )
        else
          IconButton(
            icon: const Icon(Icons.add_box_rounded),
            onPressed: () => _showAddEditItemDialog(context),
            tooltip: 'Add SKU',
          ),
      ],
      body: Column(
        children: [
          // 1. Valuation Summary Header
          valuationAsync.when(
            data: (val) {
              final (totalCount, totalQty, totalValueCents) = val;
              final formattedValuation = CurrencyFormatter.format(totalValueCents);

              if (isIos) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: LiquidGlassCard(
                    borderRadius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('$totalCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text('Total SKUs', style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
                            ],
                          ),
                          Container(width: 1, height: 32, color: CupertinoColors.systemGrey4),
                          Column(
                            children: [
                              Text(totalQty.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const Text('Total Units', style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
                            ],
                          ),
                          Container(width: 1, height: 32, color: CupertinoColors.systemGrey4),
                          Column(
                            children: [
                              Text(formattedValuation, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: CupertinoColors.activeGreen)),
                              const Text('Stock Value', style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('$totalCount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Text('Total SKUs', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                        Column(
                          children: [
                            Text(totalQty.toStringAsFixed(0), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Text('Total Units', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                        Column(
                          children: [
                            Text(formattedValuation, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                            const Text('Stock Valuation', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stack) => const SizedBox.shrink(),
          ),

          // 2. Search & Low Stock Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: isIos
                      ? CupertinoSearchTextField(
                          controller: _searchCtrl,
                          placeholder: 'Search SKU or Item Name',
                          onChanged: (val) => ref.read(inventorySearchQueryProvider.notifier).setQuery(val),
                        )
                      : TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search SKU or Item Name...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) => ref.read(inventorySearchQueryProvider.notifier).setQuery(val),
                        ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Low Stock'),
                  selected: isLowStockOnly,
                  onSelected: (val) => ref.read(inventoryLowStockFilterProvider.notifier).setFilter(val),
                ),
              ],
            ),
          ),

          // 3. Item List with swipe-down-to-refresh
          Expanded(
            child: RefreshIndicator.adaptive(
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref.invalidate(inventoryItemsListProvider);
                ref.invalidate(inventoryValuationProvider);
                await ref.read(syncControllerProvider.notifier).triggerSync();
              },
              child: itemsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(isIos ? CupertinoIcons.cube_box : Icons.inventory_2_outlined, size: 56, color: Colors.grey),
                              const SizedBox(height: 12),
                              const Text('No inventory items found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              const Text('Add your product SKUs to start tracking stock.', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    final sellFormatted = CurrencyFormatter.format(item.sellingPriceInCents);

                    if (isIos) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: LiquidGlassCard(
                          borderRadius: 16,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: item.isLowStock
                                        ? CupertinoColors.systemRed.withValues(alpha: 0.15)
                                        : CupertinoColors.activeBlue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.cube_box_fill,
                                    color: item.isLowStock ? CupertinoColors.systemRed : CupertinoColors.activeBlue,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      Text('SKU: ${item.sku} • Price: $sellFormatted', style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: item.isLowStock
                                            ? CupertinoColors.systemRed.withValues(alpha: 0.2)
                                            : CupertinoColors.systemGreen.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: item.isLowStock ? CupertinoColors.destructiveRed : CupertinoColors.activeGreen,
                                        ),
                                      ),
                                    ),
                                    if (item.isLowStock)
                                      const Text('Low Stock!', style: TextStyle(fontSize: 10, color: CupertinoColors.destructiveRed, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _showAdjustStockDialog(context, item),
                                  child: const Icon(CupertinoIcons.slider_horizontal_3, size: 20),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: item.isLowStock ? BorderSide(color: Theme.of(context).colorScheme.error, width: 1.2) : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.isLowStock
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(context).colorScheme.primaryContainer,
                          foregroundColor: item.isLowStock
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                          child: const Icon(Icons.inventory_2_rounded),
                        ),
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('SKU: ${item.sku} • Selling: $sellFormatted'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text('${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit}'),
                              backgroundColor: item.isLowStock
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(Icons.tune_rounded, size: 20),
                              tooltip: 'Adjust Stock',
                              onPressed: () => _showAdjustStockDialog(context, item),
                            ),
                          ],
                        ),
                        onTap: () => _showAddEditItemDialog(context, item),
                      ),
                    );
                  },
                );
              },
              loading: () => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                  ],
                ),
                error: (err, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(child: Text('Error: $err')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
