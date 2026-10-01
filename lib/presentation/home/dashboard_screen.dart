import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/splitting_fab.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/party_model.dart';
import '../integrations/ecommerce_sync_screen.dart';
import '../integrations/third_party_import_screen.dart';
import '../inventory/manufacturing_journal_screen.dart';
import '../payments/cts2010_cheque_preview_screen.dart';
import '../payroll/employee_list_screen.dart';
import '../profile/profile_screen.dart';
import '../../data/models/subscription_tier_model.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/subscription_providers.dart';
import '../reports/receivables_payables_screen.dart';
import '../subscription/subscription_paywall_screen.dart';
import 'add_party_dialog.dart';
import 'company_switcher_sheet.dart';
import 'dashboard_bi_hub_card.dart';
import 'dashboard_sidebar_drawer.dart';
import 'party_list_tab.dart';
import 'sync_settings_sheet.dart';

class DashboardTabNotifier extends Notifier<int> {
  @override
  int build() {
    final activeFilter = ref.watch(selectedPartyTypeFilterProvider);
    return activeFilter == PartyType.supplier ? 1 : 0;
  }

  void setTab(int index) {
    state = index;
  }
}

final dashboardTabProvider = NotifierProvider<DashboardTabNotifier, int>(DashboardTabNotifier.new);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _showErpModulesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      elevation: 0,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isIos = AdaptiveThemeHelper.isIos(ctx);
        final colorScheme = Theme.of(ctx).colorScheme;

        return Container(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 20),
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModalDragHandle(margin: EdgeInsets.only(bottom: 12)),
              const Text(
                'LedgerPulse ERP Modules',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.doc_text_fill : Icons.receipt_long_rounded,
                title: 'Receivables & Payables Tracking',
                subtitle: 'Aging buckets (0-30, 31-60, 90+ days), reminders & remittance advice',
                color: isIos ? CupertinoColors.systemGreen : colorScheme.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const ReceivablesPayablesScreen()));
                },
              ),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.money_dollar_circle_fill : Icons.payments_rounded,
                title: 'Payroll & Employee Salaries',
                subtitle: 'Employee master, PF/ESI/PT deductions & PDF salary slips',
                color: isIos ? CupertinoColors.activeBlue : colorScheme.secondary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const EmployeeListScreen()));
                },
              ),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.gear_alt_fill : Icons.precision_manufacturing_rounded,
                title: 'Manufacturing & BOM Journals',
                subtitle: 'Bill of Materials, raw material deduction & production cost',
                color: isIos ? CupertinoColors.systemOrange : colorScheme.tertiary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const ManufacturingJournalScreen()));
                },
              ),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.arrow_2_circlepath_circle_fill : Icons.sync_alt_rounded,
                title: 'Third-Party ERP & Excel Import',
                subtitle: 'Import parties and stock from Tally, Zoho, QuickBooks & Excel',
                color: isIos ? CupertinoColors.systemTeal : colorScheme.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const ThirdPartyImportScreen()));
                },
              ),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.cart_fill : Icons.shopping_cart_rounded,
                title: 'Amazon & Flipkart Sync',
                subtitle: 'Auto-sync marketplace orders into GST sales invoices',
                color: isIos ? CupertinoColors.activeOrange : colorScheme.secondary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const EcommerceSyncScreen()));
                },
              ),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.printer_fill : Icons.print_rounded,
                title: 'CTS-2010 Cheque Printing (Windows)',
                subtitle: 'Pre-calibrated bank cheque printer with MICR zone protection',
                color: isIos ? CupertinoColors.systemPurple : colorScheme.tertiary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const Cts2010ChequePreviewScreen()));
                },
              ),
              _buildModuleTile(
                context: ctx,
                icon: isIos ? CupertinoIcons.star_fill : Icons.star_rounded,
                title: 'ERP Plans & Licensing Paywall',
                subtitle: 'Manage Silver, Gold, Diamond tiers and lifetime licenses',
                color: isIos ? CupertinoColors.systemIndigo : colorScheme.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const SubscriptionPaywallScreen()));
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildModuleTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: Icon(
        isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Colors.grey,
      ),
      onTap: onTap,
    );
  }

  void _showAddPartySheet(BuildContext context, PartyType initialType) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      elevation: 0,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (context) => AddPartyDialog(initialType: initialType),
    );
  }

  void _showBiHubModal(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      elevation: 0,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => const BusinessIntelligenceSheet(),
    );
  }

  Widget? _buildAnimatedFab(
    BuildContext context,
    WidgetRef ref,
    bool isIos,
    int tabIndex,
    PartyType? activeFilter,
  ) {
    if (isIos) return null;

    final isProfileEditing = ref.watch(isProfileEditingProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Widget fabChild;
    if (tabIndex == 2) {
      fabChild = SplittingProfileFab(
        key: const ValueKey('profile_splitting_fab'),
        isEditing: isProfileEditing,
        onEdit: () {
          ref.read(isProfileEditingProvider.notifier).setEditing(true);
        },
        onSave: () {
          ref.read(profileSaveActionProvider)?.call();
        },
        onCancel: () {
          ref.read(profileCancelActionProvider)?.call();
        },
      );
    } else {
      final isSupplier = (tabIndex == 1) || (activeFilter == PartyType.supplier);
      fabChild = SpringMorphingFab(
        key: ValueKey(isSupplier ? 'supplier_add' : 'customer_add'),
        icon: Icons.person_add_rounded,
        label: isSupplier ? AppStrings.addSupplier : AppStrings.addCustomer,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        onPressed: () => _showAddPartySheet(
          context,
          isSupplier ? PartyType.supplier : PartyType.customer,
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: fabChild,
    );
  }

  static Widget _buildSubscriptionAlertBanner(BuildContext context, bool isIos, bool isDark, LicenseState sub) {
    if (!sub.isExpired && (!sub.isTrial || sub.daysRemaining > 3)) {
      return const SizedBox.shrink();
    }

    final isExpired = sub.isExpired;
    final title = isExpired
        ? 'Subscription Expired'
        : 'Trial Ending in ${sub.daysRemaining} Days';
    final message = isExpired
        ? 'Your access to advanced modules and sync is paused. Tap to renew now.'
        : 'Upgrade to keep unlimited companies, payroll, and GST e-Way bills.';

    final content = InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.of(context).push(
          createAdaptivePageRoute(builder: (_) => const SubscriptionPaywallScreen()),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isExpired ? AppColors.payableRed : Colors.amber.shade700).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isIos
                    ? (isExpired ? CupertinoIcons.exclamationmark_triangle_fill : CupertinoIcons.timer)
                    : (isExpired ? Icons.warning_rounded : Icons.timer_rounded),
                color: isExpired ? AppColors.payableRed : Colors.amber.shade700,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isExpired ? AppColors.payableRed : Colors.amber.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (isExpired ? AppColors.payableRed : AppColors.primaryBlue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'UPGRADE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isIos) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: LiquidGlassCard(
          borderRadius: 16,
          padding: EdgeInsets.zero,
          child: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: (isExpired ? AppColors.payableRed : Colors.amber.shade400).withValues(alpha: 0.6),
          ),
        ),
        color: (isExpired ? AppColors.payableRed : Colors.amber).withValues(alpha: isDark ? 0.12 : 0.06),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subscription = ref.watch(subscriptionStateProvider);

    final activeFilter = ref.watch(selectedPartyTypeFilterProvider);
    final summaryAsync = ref.watch(businessSummaryProvider);
    final isSearchActive = ref.watch(isPartySearchActiveProvider) ||
        ref.watch(partySearchQueryProvider).isNotEmpty;
    
    final tabIndex = ref.watch(dashboardTabProvider);

    return PopScope(
      canPop: !isSearchActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        HapticFeedback.lightImpact();
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(partySearchQueryProvider.notifier).setQuery('');
        ref.read(isPartySearchActiveProvider.notifier).setActive(false);
      },
      child: AdaptiveScaffold(
        drawer: DashboardSidebarDrawer(
          onOpenErpModules: () => _showErpModulesModal(context),
          onOpenBiHub: () => _showBiHubModal(context),
        ),
        titleWidget: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            CompanySwitcherSheet.show(context);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isIos ? CupertinoIcons.building_2_fill : Icons.business_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    ref.watch(activeCompanyProvider).name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isIos ? CupertinoIcons.chevron_down : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: isIos
                      ? CupertinoColors.secondaryLabel
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        actions: [
          // 1. Sync & Backup Center Button
          if (isIos)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () {
                HapticFeedback.lightImpact();
                SyncSettingsSheet.show(context);
              },
              child: const Icon(CupertinoIcons.cloud_upload_fill, size: 22),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_sync_rounded),
              tooltip: 'Sync & Backup',
              onPressed: () {
                HapticFeedback.lightImpact();
                SyncSettingsSheet.show(context);
              },
            ),
          // 2. Add Party Button (iOS)
          if (isIos)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: () => _showAddPartySheet(
                context,
                activeFilter ?? PartyType.customer,
              ),
              child: const Icon(CupertinoIcons.add, size: 22),
            ),
        ],
        // Android / Desktop / Web M3 Expressive Floating Action Button with smooth morphing transitions
        floatingActionButton: _buildAnimatedFab(context, ref, isIos, tabIndex, activeFilter),
        bottomNavigationBar: AdaptiveBottomNav(
          currentIndex: tabIndex,
          onTap: (index) {
            HapticFeedback.lightImpact();
            ref.read(dashboardTabProvider.notifier).setTab(index);
            if (index != 2) {
              ref.read(isProfileEditingProvider.notifier).setEditing(false);
              ref.read(selectedPartyTypeFilterProvider.notifier).setFilter(
                    index == 1 ? PartyType.supplier : PartyType.customer,
                  );
            }
          },
        ),
      body: tabIndex == 2 
          ? const ProfileScreen()
          : Column(
              children: [
                // Subscription / Trial Expiration Alert Banner
          _buildSubscriptionAlertBanner(context, isIos, isDark, subscription),

          // 1. Top Business Metric Cards (collapses smoothly when search is active)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOutCubic,
            firstCurve: Curves.easeIn,
            secondCurve: Curves.easeOut,
            crossFadeState: isSearchActive
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: summaryAsync.when(
                loading: () => Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Center(child: CupertinoActivityIndicator()),
                ),
                error: (err, _) => Text('Error loading metrics: $err'),
                data: (summary) {
                  final (totalReceivable, totalPayable) = summary;
                  final isDark = Theme.of(context).brightness == Brightness.dark;

                  final Widget getCardContent = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.receivableGreen.withValues(alpha: 0.2)
                                  : AppColors.receivableGreenLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isIos
                                  ? CupertinoIcons.arrow_down
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: isDark ? const Color(0xFF4ADE80) : AppColors.receivableGreen,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppStrings.youWillGet,
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark
                                  ? const Color(0xFF4ADE80)
                                  : AppColors.receivableGreenDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AmountText(
                        amountInCents: totalReceivable,
                        variant: AmountVariant.large,
                        overrideColor: isDark ? const Color(0xFF4ADE80) : AppColors.receivableGreen,
                      ),
                    ],
                  );

                  final Widget giveCardContent = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.payableRed.withValues(alpha: 0.2)
                                  : AppColors.payableRedLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isIos
                                  ? CupertinoIcons.arrow_up
                                  : Icons.arrow_upward_rounded,
                              size: 14,
                              color: isDark ? const Color(0xFFF87171) : AppColors.payableRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppStrings.youWillGive,
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark
                                  ? const Color(0xFFF87171)
                                  : AppColors.payableRedDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AmountText(
                        amountInCents: totalPayable,
                        variant: AmountVariant.large,
                        overrideColor: isDark ? const Color(0xFFF87171) : AppColors.payableRed,
                      ),
                    ],
                  );

                  return Row(
                    children: [
                      // You'll Get Card (Green)
                      Expanded(
                        child: isIos
                            ? LiquidGlassCard(
                                padding: const EdgeInsets.all(16),
                                child: getCardContent,
                              )
                            : Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: AppColors.receivableGreen.withValues(alpha: isDark ? 0.35 : 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: getCardContent,
                              ),
                      ),
                      const SizedBox(width: 12),

                      // You'll Give Card (Red)
                      Expanded(
                        child: isIos
                            ? LiquidGlassCard(
                                padding: const EdgeInsets.all(16),
                                child: giveCardContent,
                              )
                            : Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: AppColors.payableRed.withValues(alpha: isDark ? 0.35 : 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: giveCardContent,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),

          ],
        ),
        secondChild: const SizedBox(width: double.infinity, height: 0),
          ),

          // 2. Sticky Party List with search & sort
          const Expanded(
            child: PartyListTab(),
          ),
        ],
      ),
      ),
    );
  }
}
