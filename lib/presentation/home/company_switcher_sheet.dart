import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_model.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';

class CompanySwitcherSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const CompanySwitcherSheet({super.key, required this.scrollController});

  static Future<void> show(BuildContext context) {
    return showAdaptiveDraggableModal(
      context: context,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) => CompanySwitcherSheet(scrollController: scrollCtrl),
    );
  }

  @override
  ConsumerState<CompanySwitcherSheet> createState() => _CompanySwitcherSheetState();
}

class _CompanySwitcherSheetState extends ConsumerState<CompanySwitcherSheet> {
  void _showAddCompanyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final gstinCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Add New Company'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: nameCtrl,
                placeholder: 'Company Name',
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: gstinCtrl,
                placeholder: 'GSTIN (Optional)',
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: addressCtrl,
                placeholder: 'Address (Optional)',
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Create'),
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final newCmp = Company(
                    id: 'cmp_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    legalName: nameCtrl.text.trim(),
                    gstin: gstinCtrl.text.trim().isNotEmpty ? gstinCtrl.text.trim() : null,
                    address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  ref.read(companyControllerProvider.notifier).addCompany(newCmp);
                  Navigator.pop(ctx);
                }
              },
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add New Company'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Company Name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gstinCtrl,
                decoration: const InputDecoration(
                  labelText: 'GSTIN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            FilledButton(
              child: const Text('Create Company'),
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final newCmp = Company(
                    id: 'cmp_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    legalName: nameCtrl.text.trim(),
                    gstin: gstinCtrl.text.trim().isNotEmpty ? gstinCtrl.text.trim() : null,
                    address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  ref.read(companyControllerProvider.notifier).addCompany(newCmp);
                  Navigator.pop(ctx);
                }
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
    final profile = ref.watch(userProfileProvider);
    final activeCompany = ref.watch(activeCompanyProvider);
    final companies = ref.watch(userCompaniesProvider);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Switch Company',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Role: ${profile.role.displayName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isIos ? CupertinoColors.secondaryLabel : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (isIos)
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Icon(CupertinoIcons.plus_circle_fill, size: 28),
                onPressed: () => _showAddCompanyDialog(context),
              )
            else
              IconButton(
                icon: const Icon(Icons.add_business_rounded),
                onPressed: () => _showAddCompanyDialog(context),
                tooltip: 'Add Company',
              ),
          ],
        ),
        const SizedBox(height: 16),
        ...companies.map((company) {
          final isSelected = company.id == activeCompany.id;

          if (isIos) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LiquidGlassCard(
                borderRadius: 16,
                borderColor: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey4.withValues(alpha: 0.3),
                onTap: () {
                  ref.read(companyControllerProvider.notifier).selectCompany(company.id);
                  Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? CupertinoColors.activeBlue
                              : CupertinoColors.systemGrey5,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          CupertinoIcons.building_2_fill,
                          color: isSelected ? CupertinoColors.white : CupertinoColors.systemGrey,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              company.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (company.gstin != null)
                              Text(
                                'GSTIN: ${company.gstin}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.secondaryLabel,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: CupertinoColors.activeBlue,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Card(
            elevation: isSelected ? 2 : 0,
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isSelected
                  ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
                  : BorderSide.none,
            ),
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                foregroundColor: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                child: const Icon(Icons.business_rounded),
              ),
              title: Text(
                company.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                company.gstin != null ? 'GSTIN: ${company.gstin}' : company.currencyCode,
              ),
              trailing: isSelected
                  ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                ref.read(companyControllerProvider.notifier).selectCompany(company.id);
                Navigator.pop(context);
              },
            ),
          );
        }),
      ],
    );
  }
}
