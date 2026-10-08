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
    final hsnCtrl = TextEditingController(text: itemToEdit?.hsnCode ?? '');
    final unitCtrl = TextEditingController(text: itemToEdit?.unit ?? 'PCS');
    final buyPriceCtrl = TextEditingController(text: itemToEdit != null ? (itemToEdit.purchasePriceInCents / 100).toStringAsFixed(2) : '0');
    final sellPriceCtrl = TextEditingController(text: itemToEdit != null ? (itemToEdit.sellingPriceInCents / 100).toStringAsFixed(2) : '0');
    final taxRateCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.taxRatePercent.toStringAsFixed(0) : '18');
    final stockCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.currentStockQuantity.toString() : '0');
    final alertCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit.minimumStockAlert.toString() : '5');

    void onSave() {
      if (nameCtrl.text.trim().isEmpty) return;
      final buyCents = ((double.tryParse(buyPriceCtrl.text) ?? 0) * 100).round();
      final sellCents = ((double.tryParse(sellPriceCtrl.text) ?? 0) * 100).round();
      final stockQty = double.tryParse(stockCtrl.text) ?? 0.0;
      final minAlert = double.tryParse(alertCtrl.text) ?? 5.0;
      final taxRate = double.tryParse(taxRateCtrl.text) ?? 0.0;
      final hsn = hsnCtrl.text.trim().isNotEmpty ? hsnCtrl.text.trim() : null;

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
          hsnCode: hsn,
          taxRatePercent: taxRate,
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
          hsnCode: hsn,
          taxRatePercent: taxRate,
          updatedAt: DateTime.now(),
        );
        ref.read(inventoryControllerProvider.notifier).updateItem(updated);
      }
      Navigator.pop(context);
    }

    if (isIos) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: LiquidGlassCard(
              borderRadius: 28,
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          itemToEdit == null ? 'New Inventory Item' : 'Edit Item Details',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.4,
                            color: CupertinoColors.label,
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.pop(ctx),
                          child: const Icon(CupertinoIcons.xmark_circle_fill, color: CupertinoColors.secondaryLabel, size: 22),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('SKU Code *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: skuCtrl, placeholder: 'e.g. SKU-1002'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Unit of Measure', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: unitCtrl, placeholder: 'PCS, KG, BOX'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Product / Item Name *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                        const SizedBox(height: 4),
                        CupertinoTextField(controller: nameCtrl, placeholder: 'e.g. Premium Cotton Shirt'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('HSN / SAC Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: hsnCtrl, placeholder: 'e.g. 6205'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('GST Rate %', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: taxRateCtrl, placeholder: '18', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Purchase Price (₹)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: buyPriceCtrl, placeholder: '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Selling Price (₹)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: sellPriceCtrl, placeholder: '0.00', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (itemToEdit == null) ...[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Opening Stock Qty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                                const SizedBox(height: 4),
                                CupertinoTextField(controller: stockCtrl, placeholder: '0', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Low Stock Alert Level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.secondaryLabel)),
                              const SizedBox(height: 4),
                              CupertinoTextField(controller: alertCtrl, placeholder: '5', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CupertinoButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton.filled(
                          onPressed: onSave,
                          child: const Text('Save Item'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          itemToEdit == null ? 'Add Inventory SKU' : 'Edit Inventory SKU',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: skuCtrl,
                            decoration: InputDecoration(
                              labelText: 'SKU Code *',
                              hintText: 'e.g. SKU-1002',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: unitCtrl,
                            decoration: InputDecoration(
                              labelText: 'Unit *',
                              hintText: 'PCS, KG, BOX',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Product / Item Name *',
                        hintText: 'e.g. Premium Cotton Shirt',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: hsnCtrl,
                            decoration: InputDecoration(
                              labelText: 'HSN / SAC Code',
                              hintText: 'e.g. 6205',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: taxRateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'GST Rate %',
                              hintText: '18',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: buyPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Buy Price (₹)',
                              hintText: '0.00',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: sellPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Sell Price (₹)',
                              hintText: '0.00',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (itemToEdit == null) ...[
                          Expanded(
                            child: TextField(
                              controller: stockCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Initial Stock Qty',
                                hintText: '0',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: TextField(
                            controller: alertCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Low Stock Alert Level',
                              hintText: '5',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: onSave,
                          child: const Text('Save Item'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  void _showAdjustStockDialog(BuildContext context, InventoryItem item) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController(text: 'Physical inventory audit');
    StockTransactionType type = StockTransactionType.adjustment;

    void onApply(BuildContext ctx) {
      final delta = double.tryParse(qtyCtrl.text) ?? 0.0;
      ref.read(inventoryControllerProvider.notifier).adjustStock(
            itemId: item.id,
            quantityDelta: delta,
            type: type,
            note: noteCtrl.text.trim(),
          );
      Navigator.pop(ctx);
    }

    if (isIos) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LiquidGlassCard(
              borderRadius: 28,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Adjust Stock: ${item.name}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: -0.4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.pop(ctx),
                        child: const Icon(CupertinoIcons.xmark_circle_fill, color: CupertinoColors.secondaryLabel, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey6.resolveFrom(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Current Stock: ${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(controller: qtyCtrl, placeholder: 'Adjustment Quantity (+/-)', keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true)),
                  const SizedBox(height: 10),
                  CupertinoTextField(controller: noteCtrl, placeholder: 'Adjustment Reason'),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
                      const SizedBox(width: 8),
                      CupertinoButton.filled(child: const Text('Apply'), onPressed: () => onApply(ctx)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Adjust Stock: ${item.name}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Current on hand: ${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Quantity Change (e.g. +5 or -2)',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Reason / Note',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(ctx)),
                      const SizedBox(width: 8),
                      FilledButton(child: const Text('Confirm Adjustment'), onPressed: () => onApply(ctx)),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
                            prefixIcon: Icon(isIos ? CupertinoIcons.search : Icons.search),
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
