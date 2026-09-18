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
import '../auth/phone_input_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/ledger_providers.dart';
import 'add_party_dialog.dart';
import 'party_list_tab.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _showAddPartySheet(BuildContext context, PartyType initialType) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddPartyDialog(initialType: initialType),
    );
  }

  void _handleLogout(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(
          builder: (context) => const PhoneInputScreen(),
          transitionType: SharedAxisTransitionType.scaled,
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    final activeFilter = ref.watch(selectedPartyTypeFilterProvider);
    final summaryAsync = ref.watch(businessSummaryProvider);

    return AdaptiveScaffold(
      title: AppStrings.appName,
      actions: [
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
        // About / App Info button
        IconButton(
          tooltip: 'About LedgerPulse',
          icon: Icon(
            isIos ? CupertinoIcons.info_circle : Icons.info_outline_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 40,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      AppStrings.appName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v1.0.0 • Material You Ready',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.palette_outlined, size: 16, color: AppColors.primaryBlue),
                              SizedBox(width: 6),
                              Text('Material You Dynamic Theming: Active', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.android_rounded, size: 16, color: AppColors.receivableGreen),
                              SizedBox(width: 6),
                              Text('Monochrome Themed Icon: Enabled', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          },
        ),
        // Logout button
        IconButton(
          tooltip: 'Logout',
          icon: Icon(
            isIos ? CupertinoIcons.square_arrow_right : Icons.logout_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => _handleLogout(context, ref),
        ),
      ],
      // Android M3 Floating Action Button
      floatingActionButton: isIos
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddPartySheet(
                context,
                activeFilter ?? PartyType.customer,
              ),
              icon: const Icon(Icons.person_add_rounded),
              label: Text(
                activeFilter == PartyType.supplier
                    ? AppStrings.addSupplier
                    : AppStrings.addCustomer,
                style: const TextStyle(fontWeight: FontWeight.w600),
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
          // 1. Top Business Metric Cards
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: summaryAsync.when(
              loading: () => Container(
                height: 90,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
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
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.receivableGreen.withValues(alpha: 0.2)
                                : AppColors.receivableGreenLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: isDark ? const Color(0xFF4ADE80) : AppColors.receivableGreen,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.youWillGet,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark
                                ? const Color(0xFF4ADE80)
                                : AppColors.receivableGreenDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.payableRed.withValues(alpha: 0.2)
                                : AppColors.payableRedLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 14,
                            color: isDark ? const Color(0xFFF87171) : AppColors.payableRed,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.youWillGive,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark
                                ? const Color(0xFFF87171)
                                : AppColors.payableRedDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                                color: Theme.of(context).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(24),
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
                                color: Theme.of(context).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(24),
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

          // 2. Sticky Party List with search & sort animated with SharedAxisTransition
          Expanded(
            child: PageTransitionSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
                return SharedAxisTransition(
                  animation: primaryAnimation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.horizontal,
                  child: child,
                );
              },
              child: KeyedSubtree(
                key: ValueKey<PartyType?>(activeFilter),
                child: const PartyListTab(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
