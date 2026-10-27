import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_model.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/subscription_providers.dart';
import '../subscription/subscription_paywall_screen.dart';
import 'create_company_flow.dart';

void _showErrorMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  final isIos = AdaptiveThemeHelper.isIos(context);
  if (isIos) {
    showCupertinoDialog(
      context: context,
      builder: (dialogCtx) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

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

  static void showAddCompanyDialog(BuildContext context, WidgetRef ref) {
    final tier = ref.read(currentSubscriptionTierProvider);
    final companies = ref.read(userCompaniesProvider);
    if (companies.length >= tier.maxCompanies) {
      Navigator.of(context).push(
        createAdaptivePageRoute(builder: (_) => const SubscriptionPaywallScreen()),
      );
      return;
    }
    Navigator.of(context).push(
      createAdaptivePageRoute(builder: (_) => const CreateCompanyFlow()),
    );
  }

  @override
  ConsumerState<CompanySwitcherSheet> createState() => _CompanySwitcherSheetState();
}

class _CompanySwitcherSheetState extends ConsumerState<CompanySwitcherSheet> {
  void _showAddCompanyDialog(BuildContext context) {
    CompanySwitcherSheet.showAddCompanyDialog(context, ref);
  }

  void _showEditCompanyDialog(BuildContext context, Company company) {
    final nameCtrl = TextEditingController(text: company.name);
    final legalNameCtrl = TextEditingController(text: company.legalName);
    final gstinCtrl = TextEditingController(text: company.gstin ?? '');
    final addressCtrl = TextEditingController(text: company.address ?? '');
    final phoneCtrl = TextEditingController(text: company.phoneNumber ?? '');
    final emailCtrl = TextEditingController(text: company.email ?? '');
    final isIos = AdaptiveThemeHelper.isIos(context);

    final isExpense = company.mode == CompanyMode.expenseTracker;
    final modeLabel = isExpense ? 'Expense Tracker' : 'Business Ledger';

    if (isIos) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Edit Company'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: TextEditingController(text: 'Mode: $modeLabel'),
                  readOnly: true,
                  enabled: false,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: nameCtrl,
                  placeholder: 'Company Name *',
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: legalNameCtrl,
                  placeholder: 'Legal / Trade Name',
                ),
                if (!isExpense) ...[
                  const SizedBox(height: 8),
                  CupertinoTextField(
                    controller: gstinCtrl,
                    placeholder: 'GSTIN (Optional)',
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: addressCtrl,
                  placeholder: 'Address (Optional)',
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: phoneCtrl,
                  placeholder: 'Phone (Optional)',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: emailCtrl,
                  placeholder: 'Email (Optional)',
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Save'),
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final updated = company.copyWith(
                    name: nameCtrl.text.trim(),
                    legalName: legalNameCtrl.text.trim().isNotEmpty
                        ? legalNameCtrl.text.trim()
                        : nameCtrl.text.trim(),
                    gstin: !isExpense && gstinCtrl.text.trim().isNotEmpty
                        ? gstinCtrl.text.trim().toUpperCase()
                        : null,
                    address: addressCtrl.text.trim().isNotEmpty
                        ? addressCtrl.text.trim()
                        : null,
                    phoneNumber: phoneCtrl.text.trim().isNotEmpty
                        ? phoneCtrl.text.trim()
                        : null,
                    email: emailCtrl.text.trim().isNotEmpty
                        ? emailCtrl.text.trim()
                        : null,
                    updatedAt: DateTime.now(),
                  );
                  try {
                    await ref.read(companyControllerProvider.notifier).updateCompany(updated);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (context.mounted) {
                      _showErrorMessage(context, 'Failed to update company: $e');
                    }
                  }
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
          title: const Text('Edit Company'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: modeLabel),
                  readOnly: true,
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Company Mode (Read-Only)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Company Name *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: legalNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Legal Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                if (!isExpense) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: gstinCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            FilledButton(
              child: const Text('Save Changes'),
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final updated = company.copyWith(
                    name: nameCtrl.text.trim(),
                    legalName: legalNameCtrl.text.trim().isNotEmpty
                        ? legalNameCtrl.text.trim()
                        : nameCtrl.text.trim(),
                    gstin: !isExpense && gstinCtrl.text.trim().isNotEmpty
                        ? gstinCtrl.text.trim().toUpperCase()
                        : null,
                    address: addressCtrl.text.trim().isNotEmpty
                        ? addressCtrl.text.trim()
                        : null,
                    phoneNumber: phoneCtrl.text.trim().isNotEmpty
                        ? phoneCtrl.text.trim()
                        : null,
                    email: emailCtrl.text.trim().isNotEmpty
                        ? emailCtrl.text.trim()
                        : null,
                    updatedAt: DateTime.now(),
                  );
                  try {
                    await ref.read(companyControllerProvider.notifier).updateCompany(updated);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (context.mounted) {
                      _showErrorMessage(context, 'Failed to update company: $e');
                    }
                  }
                }
              },
            ),
          ],
        ),
      );
    }
  }

  void _confirmDeleteCompany(BuildContext context, Company company) {
    final companies = ref.read(userCompaniesProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (companies.length <= 1) {
      if (isIos) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Cannot Delete Company'),
            content: const Text(
              'At least one company must remain in your account. You cannot delete the only company.',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot Delete Company'),
            content: const Text(
              'At least one company must remain in your account. You cannot delete the only company.',
            ),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (isIos) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('Delete "${company.name}"?'),
          content: const Text(
            'This action will remove the company from your profile and local database. This cannot be undone.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Delete'),
              onPressed: () async {
                try {
                  final success = await ref.read(companyControllerProvider.notifier).deleteCompany(company.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!success && context.mounted) {
                    _showErrorMessage(context, 'Cannot delete the only company.');
                  }
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    _showErrorMessage(context, 'Failed to delete company: $e');
                  }
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
          title: Text('Delete "${company.name}"?'),
          content: const Text(
            'This action will remove the company from your profile and local database. This cannot be undone.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(ctx),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Delete'),
              onPressed: () async {
                try {
                  final success = await ref.read(companyControllerProvider.notifier).deleteCompany(company.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!success && context.mounted) {
                    _showErrorMessage(context, 'Cannot delete the only company.');
                  }
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    _showErrorMessage(context, 'Failed to delete company: $e');
                  }
                }
              },
            ),
          ],
        ),
      );
    }
  }

  void _showCompanyMenu(BuildContext context, Company company) {
    HapticFeedback.mediumImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);
    final activeCompany = ref.read(activeCompanyProvider);
    final isSelected = company.id == activeCompany.id;

    if (isIos) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(company.name),
          message: Text(
            isSelected
                ? 'Active Company'
                : (company.isExpense
                    ? 'Personal Expense Tracker'
                    : (company.gstin != null ? 'GSTIN: ${company.gstin}' : company.currencyCode)),
          ),
          actions: [
            if (!isSelected)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref.read(companyControllerProvider.notifier).selectCompany(company.id);
                  Navigator.pop(context);
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.checkmark_circle, size: 20),
                    SizedBox(width: 8),
                    Text('Switch to this Company'),
                  ],
                ),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showEditCompanyDialog(context, company);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.pencil, size: 20),
                  SizedBox(width: 8),
                  Text('Edit Details'),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDeleteCompany(context, company);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.trash, size: 20),
                  SizedBox(width: 8),
                  Text('Delete Company'),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      final colorScheme = Theme.of(context).colorScheme;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSelected
                            ? 'Active Company'
                            : (company.gstin != null ? 'GSTIN: ${company.gstin}' : company.currencyCode),
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (!isSelected) ...[
                        ListTile(
                          leading: const Icon(Icons.check_circle_outline_rounded),
                          title: const Text('Switch to this Company'),
                          onTap: () {
                            Navigator.pop(ctx);
                            ref.read(companyControllerProvider.notifier).selectCompany(company.id);
                            Navigator.pop(context);
                          },
                        ),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('Edit Company Details'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showEditCompanyDialog(context, company);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          'Delete Company',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _confirmDeleteCompany(context, company);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _showCompanyMenu(context, company),
                child: LiquidGlassCard(
                  borderRadius: 16,
                  borderColor: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey4.withValues(alpha: 0.3),
                  onTap: () {
                    ref.read(companyControllerProvider.notifier).selectCompany(company.id);
                    Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                              if (company.isExpense)
                                const Text(
                                  'Personal Expense Tracker',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CupertinoColors.secondaryLabel,
                                  ),
                                )
                              else if (company.gstin != null)
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
                        if (isSelected) ...[
                          const Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: CupertinoColors.activeBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                        ],
                        CupertinoButton(
                          padding: const EdgeInsets.all(4),
                          minimumSize: const Size(32, 32),
                          onPressed: () => _showCompanyMenu(context, company),
                          child: const Icon(
                            CupertinoIcons.ellipsis_vertical,
                            color: CupertinoColors.systemGrey,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
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
                company.isExpense
                    ? 'Personal Expense Tracker'
                    : (company.gstin != null ? 'GSTIN: ${company.gstin}' : company.currencyCode),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary),
                    ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Company options',
                    onPressed: () => _showCompanyMenu(context, company),
                  ),
                ],
              ),
              onTap: () {
                ref.read(companyControllerProvider.notifier).selectCompany(company.id);
                Navigator.pop(context);
              },
              onLongPress: () => _showCompanyMenu(context, company),
            ),
          );
        }),
      ],
    );
  }
}
