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
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/party_model.dart';
import '../integrations/ecommerce_sync_screen.dart';
import '../integrations/third_party_import_screen.dart';
import '../inventory/manufacturing_journal_screen.dart';
import '../payments/cts2010_cheque_preview_screen.dart';
import '../payroll/employee_list_screen.dart';
import '../profile/profile_screen.dart';
import '../providers/ledger_providers.dart';
import '../reports/reporting_hub_screen.dart';
import '../subscription/subscription_paywall_screen.dart';
import 'add_party_dialog.dart';
import 'company_switcher_sheet.dart';
import 'dashboard_bi_hub_card.dart';
import 'party_list_tab.dart';
import 'sync_settings_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _showErpModulesModal(BuildContext context) {

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Ludgerpulse ERP Modules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 12),
            _buildModuleTile(
              context: ctx,
              icon: Icons.payments_rounded,
              title: 'Payroll & Employee Salaries',
              subtitle: 'Employee master, PF/ESI/PT deductions & PDF salary slips',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const EmployeeListScreen()));
              },
            ),
            _buildModuleTile(
              context: ctx,
              icon: Icons.precision_manufacturing_rounded,
              title: 'Manufacturing & BOM Journals',
              subtitle: 'Bill of Materials, raw material deduction & production cost',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const ManufacturingJournalScreen()));
              },
            ),
            _buildModuleTile(
              context: ctx,
              icon: Icons.sync_alt_rounded,
              title: 'Third-Party ERP & Excel Import',
              subtitle: 'Import parties and stock from Tally, Zoho, QuickBooks & Excel',
              color: Colors.teal,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const ThirdPartyImportScreen()));
              },
            ),
            _buildModuleTile(
              context: ctx,
              icon: Icons.shopping_cart_rounded,
              title: 'Amazon & Flipkart Sync',
              subtitle: 'Auto-sync marketplace orders into GST sales invoices',
              color: Colors.amber.shade800,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const EcommerceSyncScreen()));
              },
            ),
            _buildModuleTile(
              context: ctx,
              icon: Icons.print_rounded,
              title: 'CTS-2010 Cheque Printing (Windows)',
              subtitle: 'Pre-calibrated bank cheque printer with MICR zone protection',
              color: Colors.purple,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const Cts2010ChequePreviewScreen()));
              },
            ),
            _buildModuleTile(
              context: ctx,
              icon: Icons.star_rounded,
              title: 'ERP Plans & Licensing Paywall',
              subtitle: 'Manage Silver, Gold, Diamond tiers and lifetime licenses',
              color: const Color(0xFF7C3AED),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(createAdaptivePageRoute(builder: (_) => const SubscriptionPaywallScreen()));
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
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
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showAddPartySheet(BuildContext context, PartyType initialType) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (context) => AddPartyDialog(initialType: initialType),
    );
  }

  void _openProfile(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      createAdaptivePageRoute(
        builder: (context) => const ProfileScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    final activeFilter = ref.watch(selectedPartyTypeFilterProvider);
    final summaryAsync = ref.watch(businessSummaryProvider);
    final isSearchActive = ref.watch(isPartySearchActiveProvider) ||
        ref.watch(partySearchQueryProvider).isNotEmpty;

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
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icons/app_icon.png',
                height: 28,
                width: 28,
              ),
            ),
            const SizedBox(width: 8),
            const Text(AppStrings.appName),
          ],
        ),
        actions: [
          // Sync Center button
        IconButton(
          tooltip: 'Sync & Backup',
          icon: Icon(
            isIos ? CupertinoIcons.cloud_upload : Icons.sync_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => SyncSettingsSheet.show(context),
        ),

        // Company Switcher button
        IconButton(
          tooltip: 'Switch Company',
          icon: Icon(
            isIos ? CupertinoIcons.building_2_fill : Icons.business_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => CompanySwitcherSheet.show(context),
        ),

        // Reports & Analytics Hub
        IconButton(
          tooltip: 'Reports & Analytics Hub',
          icon: Icon(
            isIos ? CupertinoIcons.chart_pie : Icons.insights_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              createAdaptivePageRoute(builder: (context) => const ReportingHubScreen()),
            );
          },
        ),

        // ERP Modules Hub (Payroll, Manufacturing, Importers, Cheque Printing, Paywall)
        IconButton(
          tooltip: 'ERP Modules & Paywall',
          icon: Icon(
            isIos ? CupertinoIcons.square_grid_2x2 : Icons.apps_rounded,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            _showErpModulesModal(context);
          },
        ),

        // iOS Add Party Action in navigation bar
        if (isIos)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () => _showAddPartySheet(
              context,
              activeFilter ?? PartyType.customer,
            ),
            child: const Icon(CupertinoIcons.add, size: 22),
          ),

        // Profile button
        IconButton(
          tooltip: 'Profile',
          icon: Icon(
            isIos ? CupertinoIcons.person_crop_circle : Icons.account_circle_outlined,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => _openProfile(context),
        ),
      ],
      // Android M3 Expressive Floating Action Button
      floatingActionButton: isIos
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddPartySheet(
                context,
                activeFilter ?? PartyType.customer,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              icon: const Icon(Icons.person_add_rounded),
              label: Text(
                activeFilter == PartyType.supplier
                    ? AppStrings.addSupplier
                    : AppStrings.addCustomer,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
      bottomNavigationBar: AdaptiveBottomNav(
        currentIndex: activeFilter == PartyType.supplier ? 1 : 0,
        onTap: (index) {
          HapticFeedback.lightImpact();
          ref.read(selectedPartyTypeFilterProvider.notifier).setFilter(
                index == 1 ? PartyType.supplier : PartyType.customer,
              );
        },
      ),
      body: Column(
        children: [
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
                              Icons.arrow_downward_rounded,
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
                              Icons.arrow_upward_rounded,
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
            const DashboardBiHubCard(),
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
