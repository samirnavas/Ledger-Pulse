import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/amount_text.dart';
import '../../data/models/party_model.dart';
import '../auth/phone_input_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/ledger_providers.dart';
import 'add_party_dialog.dart';
import 'party_list_tab.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  void _showAddPartySheet(BuildContext context, PartyType initialType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddPartyDialog(initialType: initialType),
    );
  }

  void _handleLogout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PhoneInputScreen()),
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
            color: AppColors.textSecondaryLight,
          ),
          onPressed: () {
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
                    const Text(
                      'v1.0.0 • Material You Ready',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCardM3,
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
            color: AppColors.textSecondaryLight,
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
      body: Column(
        children: [
          // 1. Top Business Metric Cards
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: summaryAsync.when(
              loading: () => Container(
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(child: CupertinoActivityIndicator()),
              ),
              error: (err, _) => Text('Error loading metrics: $err'),
              data: (summary) {
                final (totalReceivable, totalPayable) = summary;

                return Row(
                  children: [
                    // You'll Get Card (Green)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isIos
                              ? CupertinoColors.white
                              : AppColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.receivableGreen.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.receivableGreen.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.receivableGreenLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 14,
                                    color: AppColors.receivableGreen,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  AppStrings.youWillGet,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.receivableGreenDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AmountText(
                              amountInCents: totalReceivable,
                              variant: AmountVariant.large,
                              overrideColor: AppColors.receivableGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // You'll Give Card (Red)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isIos
                              ? CupertinoColors.white
                              : AppColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.payableRed.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.payableRed.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.payableRedLight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 14,
                                    color: AppColors.payableRed,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  AppStrings.youWillGive,
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.payableRedDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AmountText(
                              amountInCents: totalPayable,
                              variant: AmountVariant.large,
                              overrideColor: AppColors.payableRed,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 2. Adaptive Segmented Control (Customers vs Suppliers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: AdaptiveSegmentedControl<PartyType>(
              groupValue: activeFilter ?? PartyType.customer,
              children: const {
                PartyType.customer: Text(
                  AppStrings.customersTab,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                PartyType.supplier: Text(
                  AppStrings.suppliersTab,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              },
              onValueChanged: (type) {
                ref.read(selectedPartyTypeFilterProvider.notifier).setFilter(type);
              },
            ),
          ),

          // 3. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: isIos ? CupertinoColors.white : AppColors.surfaceWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight, width: 1),
              ),
              child: TextField(
                onChanged: (val) {
                  ref.read(partySearchQueryProvider.notifier).setQuery(val);
                },
                decoration: InputDecoration(
                  hintText: AppStrings.searchHint,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMutedLight,
                  ),
                  prefixIcon: Icon(
                    isIos ? CupertinoIcons.search : Icons.search_rounded,
                    size: 18,
                    color: AppColors.textMutedLight,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // 4. Party List
          const Expanded(
            child: PartyListTab(),
          ),
        ],
      ),
    );
  }
}
