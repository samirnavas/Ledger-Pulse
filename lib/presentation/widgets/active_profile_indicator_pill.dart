import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../home/company_switcher_sheet.dart';
import '../providers/company_providers.dart';
import '../providers/profile_session_controller.dart';
import '../providers/profile_session_state.dart';

/// Platform-adaptive title pill indicating the current active profile/workspace.
///
/// Features:
/// - Distinct visual indicators for Personal Expense vs Business Ledger
/// - Role badge (Owner, Admin, Member)
/// - Single tap triggers safe profile switching modal sheet
/// - Follows Material 3 Expressive on Android and Liquid Glass on iOS
class ActiveProfileIndicatorPill extends ConsumerWidget {
  final VoidCallback? onTap;

  const ActiveProfileIndicatorPill({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final sessionState = ref.watch(profileSessionProvider);
    final fallbackCompany = ref.watch(activeCompanyProvider);

    final String displayName;
    final bool isExpense;
    final String roleName;

    if (sessionState is ActiveProfileReadySessionState) {
      final active = sessionState.activeProfile;
      displayName = active.name.isNotEmpty ? active.name : fallbackCompany.name;
      isExpense = active.isExpense;
      roleName = active.role.displayName;
    } else {
      displayName = fallbackCompany.name;
      isExpense = fallbackCompany.isExpense;
      roleName = 'Owner';
    }

    final accentColor =
        isExpense ? AppColors.primaryGreen : AppColors.primaryBlue;

    return InkWell(
      key: const Key('active_profile_indicator_pill'),
      onTap: () {
        HapticFeedback.lightImpact();
        if (onTap != null) {
          onTap!();
        } else {
          CompanySwitcherSheet.show(context);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Domain Icon Badge
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExpense
                    ? (isIos
                        ? CupertinoIcons.money_dollar_circle_fill
                        : Icons.account_balance_wallet_rounded)
                    : (isIos
                        ? CupertinoIcons.building_2_fill
                        : Icons.business_rounded),
                size: 16,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 8),

            // Profile Title & Type
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          displayName.isNotEmpty ? displayName : 'My Workspace',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isIos
                            ? CupertinoIcons.chevron_down
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isExpense ? 'PERSONAL' : 'BUSINESS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        roleName,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

