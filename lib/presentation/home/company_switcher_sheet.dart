import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_model.dart';
import '../auth/profile_onboarding_screen.dart';
import '../expense/quick_add_transaction_sheet.dart';
import '../providers/auth_providers.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/profile_session_controller.dart';
import '../providers/profile_session_state.dart';
import 'edit_profile_sheet.dart';

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
      builder: (ctx, scrollCtrl) =>
          CompanySwitcherSheet(scrollController: scrollCtrl),
    );
  }

  static void showAddCompanyDialog(BuildContext context, WidgetRef ref) {
    final authState = ref.read(authControllerProvider);
    final userId =
        authState.userId ?? ref.read(authRepositoryProvider).currentUserId;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to add a workspace.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      createAdaptivePageRoute(
        builder: (_) => ProfileOnboardingScreen(userId: userId),
      ),
    );
  }

  @override
  ConsumerState<CompanySwitcherSheet> createState() =>
      _CompanySwitcherSheetState();
}

class _CompanySwitcherSheetState extends ConsumerState<CompanySwitcherSheet> {
  bool _switching = false;

  Future<void> _switchWorkspace(Company company) async {
    if (_switching || QuickAddTransactionSheet.isSheetOpen) return;
    if (ref.read(activeCompanyProvider).id == company.id) {
      Navigator.pop(context);
      return;
    }
    _switching = true;
    final route = ModalRoute.of(context);
    final sessionState = ref.read(profileSessionProvider);
    try {
      if (sessionState is ActiveProfileReadySessionState) {
        final match = sessionState.availableProfiles
            .where((p) => p.id == company.id)
            .firstOrNull;
        if (match == null) return;
        await ref.read(profileSessionProvider.notifier).switchProfile(match);
      } else {
        await ref.read(companyControllerProvider.notifier).selectCompany(company.id);
      }
      if (mounted && route?.isCurrent == true) Navigator.pop(context);
    } finally {
      _switching = false;
    }
  }

  void _showAddCompanyDialog(BuildContext context) {
    CompanySwitcherSheet.showAddCompanyDialog(context, ref);
  }

  void _showEditCompanyDialog(BuildContext context, Company company) {
    showEditProfileSheet(context, company);
  }

  void _confirmDeleteCompany(BuildContext context, Company company) {
    final companies = ref.read(userCompaniesProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (companies.length <= 1) {
      if (isIos) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Cannot Delete Workspace'),
            content: const Text(
              'At least one workspace must remain in your account.',
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
            title: const Text('Cannot Delete Workspace'),
            content: const Text(
              'At least one workspace must remain in your account.',
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
            'This permanently deletes the workspace.',
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
                  final success = await ref
                      .read(companyControllerProvider.notifier)
                      .deleteCompany(company.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!success && context.mounted) {
                    _showErrorMessage(
                      context,
                      'Your account must keep at least one workspace.',
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    _showErrorMessage(context, 'Failed to delete workspace: $e');
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
            'This permanently deletes the workspace.',
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
                  final success = await ref
                      .read(companyControllerProvider.notifier)
                      .deleteCompany(company.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (!success && context.mounted) {
                    _showErrorMessage(
                      context,
                      'Your account must keep at least one workspace.',
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    _showErrorMessage(context, 'Failed to delete workspace: $e');
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
                ? 'Active Workspace'
                : (company.isExpense
                      ? 'Personal Expense Tracker'
                      : company.currencyCode),
          ),
          actions: [
            if (!isSelected)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(ctx);
                  _switchWorkspace(company);
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.checkmark_circle, size: 20),
                    SizedBox(width: 8),
                    Text('Switch to this Workspace'),
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
                  Text('Edit Workspace'),
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
                  Text('Delete Workspace'),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
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
                            ? 'Active Workspace'
                            : company.currencyCode,
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
                          leading: const Icon(
                            Icons.check_circle_outline_rounded,
                          ),
                          title: const Text('Switch to this Workspace'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _switchWorkspace(company);
                          },
                        ),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('Edit Workspace'),
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
                          'Delete Workspace',
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Switch Workspace',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isIos
                          ? CupertinoColors.label
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Role: ${profile.role.displayName}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isIos
                          ? CupertinoColors.secondaryLabel
                          : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
                tooltip: 'Add Workspace',
              ),
          ],
        ),
        const SizedBox(height: 16),
        ...companies.map((company) {
          final isSelected = company.id == activeCompany.id;
          final profileType =
              company.isExpense ? 'Personal Expense Tracker' : 'Business Ledger';

          if (isIos) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _showCompanyMenu(context, company),
                child: LiquidGlassCard(
                  borderRadius: 16,
                  borderColor: isSelected
                      ? CupertinoColors.activeBlue
                      : CupertinoColors.systemGrey4.withValues(alpha: 0.3),
                  onTap: () => _switchWorkspace(company),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? CupertinoTheme.of(context).primaryColor
                                : CupertinoColors.systemGrey5,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            company.isExpense
                                ? CupertinoIcons.money_dollar_circle_fill
                                : CupertinoIcons.building_2_fill,
                            color: isSelected
                                ? CupertinoColors.white
                                : CupertinoColors.systemGrey,
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
                              Text(
                                profileType,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.secondaryLabel,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected) ...[
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: CupertinoTheme.of(context).primaryColor,
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
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    )
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
                child: Icon(
                  company.isExpense
                      ? Icons.account_balance_wallet_rounded
                      : Icons.business_rounded,
                ),
              ),
              title: Text(
                company.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(profileType),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Workspace options',
                    onPressed: () => _showCompanyMenu(context, company),
                  ),
                ],
              ),
              onTap: () => _switchWorkspace(company),
              onLongPress: () => _showCompanyMenu(context, company),
            ),
          );
        }),
      ],
    );
  }
}
