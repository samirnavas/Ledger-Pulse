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
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
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
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: summaryAsync.when(
                loading: () => Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                                  color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                                  color: Theme.of(context).colorScheme.surfaceContainerLow,
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
            secondChild: const SizedBox(width: double.infinity, height: 0),
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
      ),
    );
  }
}
