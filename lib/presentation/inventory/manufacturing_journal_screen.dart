import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/accounting/manufacturing_journal_engine.dart';
import '../../data/models/manufacturing_bom_model.dart';
import '../providers/company_providers.dart';
import '../providers/inventory_providers.dart';
import '../providers/profile_provider.dart';

final sampleBomsProvider = Provider<List<BillOfMaterials>>((ref) {
  final company = ref.watch(activeCompanyProvider);
  return [
    BillOfMaterials(
      id: 'bom_desktop_assembled',
      companyId: company.id,
      bomName: 'Pro Assembly: Desktop Workstation Core i7',
      finishedGoodsItemId: 'itm_1',
      finishedGoodsSku: 'SYS-DT-01',
      finishedGoodsName: 'Desktop Computer Pro Core i7',
      outputQuantity: 1.0,
      outputUnit: 'UNIT',
      rawMaterials: const [
        BomRawMaterialItem(
          rawMaterialItemId: 'itm_2',
          rawMaterialSku: 'MEM-DDR5-16',
          rawMaterialName: 'RAM DDR5 16GB Module',
          quantityRequired: 2.0,
          unit: 'PCS',
          unitCostInCents: 450000, // ₹4,500 each
          wastagePercentage: 0.0,
        ),
        BomRawMaterialItem(
          rawMaterialItemId: 'itm_3',
          rawMaterialSku: 'SSD-NVME-1TB',
          rawMaterialName: 'NVMe Gen4 1TB SSD',
          quantityRequired: 1.0,
          unit: 'PCS',
          unitCostInCents: 620000, // ₹6,200
          wastagePercentage: 0.0,
        ),
      ],
      directLaborCostInCents: 150000,    // ₹1,500
      electricityOverheadInCents: 50000,  // ₹500
      machineOverheadInCents: 30000,     // ₹300
      createdAt: DateTime.now(),
    ),
  ];
});

class ManufacturingJournalScreen extends ConsumerStatefulWidget {
  const ManufacturingJournalScreen({super.key});

  @override
  ConsumerState<ManufacturingJournalScreen> createState() =>
      _ManufacturingJournalScreenState();
}

class _ManufacturingJournalScreenState
    extends ConsumerState<ManufacturingJournalScreen> {
  BillOfMaterials? _selectedBom;
  final TextEditingController _quantityController = TextEditingController(text: '1');
  bool _isExecuting = false;
  ManufacturingExecutionResult? _lastResult;

  @override
  void initState() {
    super.initState();
    final boms = ref.read(sampleBomsProvider);
    if (boms.isNotEmpty) {
      _selectedBom = boms.first;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  double get _productionQty => double.tryParse(_quantityController.text.trim()) ?? 1.0;

  Future<void> _runProduction() async {
    if (_selectedBom == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isExecuting = true;
      _lastResult = null;
    });

    final company = ref.read(activeCompanyProvider);
    final profile = ref.read(userProfileProvider);
    final engine = ref.read(manufacturingJournalEngineProvider);

    final result = await engine.executeProductionRun(
      bom: _selectedBom!,
      productionQuantity: _productionQty,
      companyId: company.id,
      userId: profile.id,
    );

    if (mounted) {
      setState(() {
        _isExecuting = false;
        _lastResult = result;
      });

      if (result.success) {
        ref.invalidate(inventoryItemsListProvider);
        ref.invalidate(inventoryValuationProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Manufacturing Journal ${result.voucherNumber} posted! Finished Goods stock updated.',
            ),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Manufacturing execution failed.'),
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
    final boms = ref.watch(sampleBomsProvider);
    final bom = _selectedBom;

    final scaleFactor = _productionQty / (bom != null && bom.outputQuantity > 0 ? bom.outputQuantity : 1.0);
    final totalRawCost = bom != null ? (bom.totalRawMaterialsCostInCents * scaleFactor).round() : 0;
    final totalOverhead = bom != null ? (bom.totalOverheadsCostInCents * scaleFactor).round() : 0;
    final totalCost = totalRawCost + totalOverhead;
    final unitCost = _productionQty > 0 ? (totalCost / _productionQty).round() : totalCost;

    return AdaptiveScaffold(
      title: 'Manufacturing & BOM Journal',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // BOM Selector
            DropdownButtonFormField<BillOfMaterials>(
              initialValue: _selectedBom,
              decoration: InputDecoration(
                labelText: 'Select Bill of Materials (BOM)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                prefixIcon: Icon(
                  isIos ? CupertinoIcons.hammer_fill : Icons.precision_manufacturing_rounded,
                ),
                isDense: true,
                filled: true,
                fillColor: isIos
                    ? (isDark
                        ? CupertinoColors.systemGrey6.darkColor
                        : CupertinoColors.systemGrey6)
                    : Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
              items: boms.map((b) {
                return DropdownMenuItem(
                  value: b,
                  child: Text(b.bomName, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedBom = val);
              },
            ),
            const SizedBox(height: 14),

            // Production Quantity Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Production Batch Quantity (${bom?.outputUnit ?? "Units"})',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      prefixIcon: Icon(
                        isIos ? CupertinoIcons.number : Icons.pin_rounded,
                      ),
                      filled: true,
                      fillColor: isIos
                          ? (isDark
                              ? CupertinoColors.systemGrey6.darkColor
                              : CupertinoColors.systemGrey6)
                          : Theme.of(context).colorScheme.surfaceContainerLowest,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (bom != null) ...[
              // Finished Good Output Summary Box
              _buildFinishedGoodCard(isIos, isDark, bom, _productionQty, unitCost, totalCost),
              const SizedBox(height: 16),

              // Raw Materials Required Table
              const Text('Raw Materials Consumption Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),

              ...bom.rawMaterials.map((raw) {
                final needed = raw.quantityRequired * scaleFactor * (1.0 + (raw.wastagePercentage / 100.0));
                final cost = (needed * raw.unitCostInCents).round();

                final itemTile = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.square_stack_3d_up_fill : Icons.layers_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(raw.rawMaterialName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('SKU: ${raw.rawMaterialSku} • ₹${(raw.unitCostInCents / 100.0).toStringAsFixed(2)} / ${raw.unit}',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${needed.toStringAsFixed(1)} ${raw.unit}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('₹ ${(cost / 100.0).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                );

                if (isIos) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LiquidGlassCard(borderRadius: 18, padding: EdgeInsets.zero, child: itemTile),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5)),
                    ),
                    child: itemTile,
                  ),
                );
              }),
              const SizedBox(height: 16),

              // Production Run Action Button
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  onPressed: _isExecuting ? () {} : _runProduction,
                  child: _isExecuting
                      ? const CupertinoActivityIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isIos ? CupertinoIcons.bolt_fill : Icons.bolt_rounded,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Execute Production Run & Adjust Stock',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),

              if (_lastResult != null) ...[
                const SizedBox(height: 16),
                _buildExecutionResult(isIos, isDark, _lastResult!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinishedGoodCard(
    bool isIos,
    bool isDark,
    BillOfMaterials bom,
    double qty,
    int unitCost,
    int totalCost,
  ) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Output: ${bom.finishedGoodsName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${qty.toStringAsFixed(1)} ${bom.outputUnit}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlue, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Calculated Unit Cost', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text('₹ ${(unitCost / 100.0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total Production Cost', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text('₹ ${(totalCost / 100.0).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.receivableGreen)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(borderRadius: 22, padding: EdgeInsets.zero, child: content);
    }
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: AppColors.primaryBlue.withValues(alpha: 0.4)),
      ),
      child: content,
    );
  }

  Widget _buildExecutionResult(bool isIos, bool isDark, ManufacturingExecutionResult res) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              res.success
                  ? (isIos
                      ? CupertinoIcons.checkmark_circle_fill
                      : Icons.check_circle_rounded)
                  : (isIos
                      ? CupertinoIcons.exclamationmark_triangle_fill
                      : Icons.error_outline_rounded),
              color: res.success ? AppColors.receivableGreen : AppColors.payableRed,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              res.success ? 'Production Run Completed' : 'Production Run Blocked',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: res.success ? AppColors.receivableGreen : AppColors.payableRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (res.success) ...[
          Text('Voucher: ${res.voucherNumber} • Total Batch Value: ₹${(res.totalCostInCents / 100.0).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          ...res.rawMaterialsConsumedSummary.map((s) => Text('• $s', style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ] else ...[
          Text(res.errorMessage ?? 'Error occurred.', style: const TextStyle(fontSize: 12)),
        ],
      ],
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 20,
        borderColor: res.success ? AppColors.receivableGreen.withValues(alpha: 0.5) : AppColors.payableRed.withValues(alpha: 0.5),
        child: content,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: res.success
            ? AppColors.receivableGreen.withValues(alpha: 0.1)
            : AppColors.payableRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: res.success
              ? AppColors.receivableGreen.withValues(alpha: 0.6)
              : AppColors.payableRed.withValues(alpha: 0.6),
        ),
      ),
      child: content,
    );
  }
}
