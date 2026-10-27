import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/adaptive_button.dart';
import '../../../core/widgets/adaptive_segmented_control.dart';
import '../../../data/models/inventory_item_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../providers/inventory_providers.dart';

/// Modal bottom sheet to search and select stock inventory items or customize non-stock service lines.
class VoucherItemSelectorModal extends ConsumerStatefulWidget {
  final VoucherType voucherType;
  final bool initialIsService;
  final ValueChanged<VoucherItemModel> onItemAdded;

  const VoucherItemSelectorModal({
    super.key,
    required this.voucherType,
    this.initialIsService = false,
    required this.onItemAdded,
  });

  @override
  ConsumerState<VoucherItemSelectorModal> createState() =>
      _VoucherItemSelectorModalState();
}

class _VoucherItemSelectorModalState
    extends ConsumerState<VoucherItemSelectorModal> {
  late bool _isServiceMode;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Selected Inventory Item config state
  InventoryItem? _selectedItem;
  final TextEditingController _itemQtyController = TextEditingController(text: '1');
  final TextEditingController _itemRateController = TextEditingController();
  final TextEditingController _itemTaxRateController = TextEditingController(text: '18');
  final TextEditingController _itemHsnController = TextEditingController();

  // Service Line form state
  final TextEditingController _serviceNameController = TextEditingController();
  final TextEditingController _serviceHsnController = TextEditingController(text: '9983');
  final TextEditingController _serviceQtyController = TextEditingController(text: '1');
  final TextEditingController _serviceUnitController = TextEditingController(text: 'HRS');
  final TextEditingController _serviceRateController = TextEditingController(text: '1000');
  final TextEditingController _serviceTaxRateController = TextEditingController(text: '18');

  @override
  void initState() {
    super.initState();
    _isServiceMode = widget.initialIsService;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _itemQtyController.dispose();
    _itemRateController.dispose();
    _itemTaxRateController.dispose();
    _itemHsnController.dispose();
    _serviceNameController.dispose();
    _serviceHsnController.dispose();
    _serviceQtyController.dispose();
    _serviceUnitController.dispose();
    _serviceRateController.dispose();
    _serviceTaxRateController.dispose();
    super.dispose();
  }

  void _selectInventoryItem(InventoryItem item) {
    setState(() {
      _selectedItem = item;
      _itemQtyController.text = '1';
      final price = widget.voucherType == VoucherType.purchase
          ? (item.purchasePriceInCents > 0 ? item.purchasePriceInCents : item.sellingPriceInCents)
          : item.sellingPriceInCents;
      _itemRateController.text = (price / 100.0).toStringAsFixed(2);
      _itemTaxRateController.text = item.taxRatePercent.toStringAsFixed(0);
      _itemHsnController.text = item.hsnCode ?? '';
    });
  }

  void _addSelectedItemToInvoice() {
    if (_selectedItem == null) return;
    final qty = double.tryParse(_itemQtyController.text) ?? 1.0;
    final defaultPrice = widget.voucherType == VoucherType.purchase
        ? (_selectedItem!.purchasePriceInCents > 0 ? _selectedItem!.purchasePriceInCents : _selectedItem!.sellingPriceInCents)
        : _selectedItem!.sellingPriceInCents;
    final rate = double.tryParse(_itemRateController.text) ?? (defaultPrice / 100.0);
    final taxRate = double.tryParse(_itemTaxRateController.text) ?? _selectedItem!.taxRatePercent;
    final unitPriceCents = (rate * 100).round();
    final grossCents = (unitPriceCents * qty).round();
    final taxCents = ((grossCents * taxRate) / 100.0).round();

    final voucherItem = VoucherItemModel(
      itemId: _selectedItem!.id,
      itemName: _selectedItem!.name,
      sku: _selectedItem!.sku.isNotEmpty
          ? _selectedItem!.sku
          : 'SKU-${_selectedItem!.name.substring(0, _selectedItem!.name.length.clamp(1, 3)).toUpperCase()}',
      hsnCode: _itemHsnController.text.trim().isNotEmpty
          ? _itemHsnController.text.trim()
          : (_selectedItem!.hsnCode ?? ''),
      quantity: qty,
      unit: _selectedItem!.unit,
      unitPriceInCents: unitPriceCents,
      taxRatePercent: taxRate,
      totalInCents: grossCents + taxCents,
    );

    widget.onItemAdded(voucherItem);
    Navigator.of(context).pop();
  }

  void _addServiceLineToInvoice() {
    final name = _serviceNameController.text.trim();
    if (name.isEmpty) return;
    final qty = double.tryParse(_serviceQtyController.text) ?? 1.0;
    final rate = double.tryParse(_serviceRateController.text) ?? 0.0;
    final taxRate = double.tryParse(_serviceTaxRateController.text) ?? 18.0;
    final unit = _serviceUnitController.text.trim().isNotEmpty
        ? _serviceUnitController.text.trim()
        : 'HRS';
    final unitPriceCents = (rate * 100).round();
    final grossCents = (unitPriceCents * qty).round();
    final taxCents = ((grossCents * taxRate) / 100.0).round();

    final voucherItem = VoucherItemModel(
      itemId: 'srv_${DateTime.now().millisecondsSinceEpoch}',
      itemName: name,
      sku: 'SRV-${name.substring(0, name.length.clamp(1, 3)).toUpperCase()}',
      hsnCode: _serviceHsnController.text.trim(),
      quantity: qty,
      unit: unit,
      unitPriceInCents: unitPriceCents,
      taxRatePercent: taxRate,
      totalInCents: grossCents + taxCents,
    );

    widget.onItemAdded(voucherItem);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(inventoryItemsListProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (ctx, scrollController) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            decoration: BoxDecoration(
              color: isIos
                  ? CupertinoColors.systemBackground.resolveFrom(context)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isIos
                          ? CupertinoColors.systemGrey4
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add Line Item',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: isIos ? -0.4 : 0,
                        color: isIos
                            ? CupertinoColors.label
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: Icon(isIos ? CupertinoIcons.xmark : Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Tab Selector
                AdaptiveSegmentedControl<bool>(
                  groupValue: _isServiceMode,
                  children: const {
                    false: Text('📦 Item Master (Stock)'),
                    true: Text('⚡ Service (Non-Stock)'),
                  },
                  onValueChanged: (val) {
                    setState(() {
                      _isServiceMode = val;
                      _selectedItem = null;
                    });
                  },
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: _isServiceMode
                      ? _buildServiceForm()
                      : _selectedItem != null
                          ? _buildItemCustomizer()
                          : _buildInventoryList(itemsAsync, scrollController, isIos),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryList(
    AsyncValue<List<InventoryItem>> itemsAsync,
    ScrollController scroll,
    bool isIos,
  ) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search items by name, SKU, HSN...',
            prefixIcon: Icon(isIos ? CupertinoIcons.search : Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      isIos ? CupertinoIcons.clear_circled_solid : Icons.clear_rounded,
                      size: 18,
                    ),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                  )
                : null,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              final filtered = items.where((item) {
                if (_searchQuery.isEmpty) return true;
                final nameMatch = item.name.toLowerCase().contains(_searchQuery);
                final skuMatch = item.sku.toLowerCase().contains(_searchQuery);
                final hsnMatch = item.hsnCode?.toLowerCase().contains(_searchQuery) ?? false;
                return nameMatch || skuMatch || hsnMatch;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.cube_box : Icons.inventory_2_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No inventory items in Item Master'
                            : 'No items matching "$_searchQuery"',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Add items in the Inventory screen or add as a Service Line.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                controller: scroll,
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final item = filtered[index];
                  final priceCents = widget.voucherType == VoucherType.purchase
                      ? (item.purchasePriceInCents > 0
                          ? item.purchasePriceInCents
                          : item.sellingPriceInCents)
                      : item.sellingPriceInCents;
                  final stockColor = item.currentStockQuantity > 5
                      ? AppColors.receivableGreen
                      : item.currentStockQuantity > 0
                          ? Colors.amber.shade800
                          : Colors.red;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                      child: Text(
                        item.name.substring(0, item.name.length.clamp(1, 2)).toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Text(
                          '₹${(priceCents / 100.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          'SKU: ${item.sku.isNotEmpty ? item.sku : "-"} • HSN: ${item.hsnCode ?? "-"} • GST ${item.taxRatePercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit} in stock',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: stockColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Icon(
                      isIos ? CupertinoIcons.chevron_right : Icons.chevron_right_rounded,
                      size: 16,
                      color: Colors.grey,
                    ),
                    onTap: () => _selectInventoryItem(item),
                  );
                },
              );
            },
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (err, _) => Center(child: Text('Error loading inventory: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCustomizer() {
    final item = _selectedItem!;
    final qty = double.tryParse(_itemQtyController.text) ?? 1.0;
    final defaultPrice = widget.voucherType == VoucherType.purchase
        ? (item.purchasePriceInCents > 0 ? item.purchasePriceInCents : item.sellingPriceInCents)
        : item.sellingPriceInCents;
    final rate = double.tryParse(_itemRateController.text) ?? (defaultPrice / 100.0);
    final taxRate = double.tryParse(_itemTaxRateController.text) ?? item.taxRatePercent;
    final totalCents = ((rate * 100 * qty) * (1 + (taxRate / 100.0))).round();
    final isIos = AdaptiveThemeHelper.isIos(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(isIos ? CupertinoIcons.back : Icons.arrow_back_rounded),
                onPressed: () => setState(() => _selectedItem = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      'SKU: ${item.sku.isNotEmpty ? item.sku : "-"} • Stock: ${item.currentStockQuantity.toStringAsFixed(0)} ${item.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemQtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Quantity (${item.unit})',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _itemRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: widget.voucherType == VoucherType.purchase
                        ? 'Purchase Rate (₹)'
                        : 'Selling Rate (₹)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _itemHsnController,
                  decoration: const InputDecoration(
                    labelText: 'HSN / SAC Code',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _itemTaxRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'GST Rate %',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Line Amount (incl. GST):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  CurrencyFormatter.format(totalCents),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.receivableGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AdaptiveButton(
            onPressed: _addSelectedItemToInvoice,
            type: AdaptiveButtonType.primary,
            child: Text('Add to ${widget.voucherType.displayName}'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceForm() {
    final qty = double.tryParse(_serviceQtyController.text) ?? 1.0;
    final rate = double.tryParse(_serviceRateController.text) ?? 0.0;
    final taxRate = double.tryParse(_serviceTaxRateController.text) ?? 18.0;
    final totalCents = ((rate * 100 * qty) * (1 + (taxRate / 100.0))).round();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _serviceNameController,
            decoration: const InputDecoration(
              labelText: 'Service Name / Description',
              hintText: 'e.g. Legal Consulting, Software Maintenance',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serviceHsnController,
                  decoration: const InputDecoration(
                    labelText: 'SAC / HSN Code',
                    hintText: '9983',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit (e.g. HRS, NOS, JOB)',
                    border: OutlineInputBorder(),
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
                  controller: _serviceQtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Quantity / Hours',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Unit Rate (₹)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _serviceTaxRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'GST Rate %',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Service Amount (incl. GST):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  CurrencyFormatter.format(totalCents),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AdaptiveButton(
            onPressed: _addServiceLineToInvoice,
            type: AdaptiveButtonType.primary,
            child: Text('Add Service Line to ${widget.voucherType.displayName}'),
          ),
        ],
      ),
    );
  }
}
