import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../domain/models/workspace_profile_header.dart';
import '../providers/auth_providers.dart';
import '../providers/profile_session_controller.dart';
import '../providers/profile_session_state.dart';
import 'app_root_gate.dart';
import 'profile_onboarding_screen.dart';

class ProfileSelectorScreen extends ConsumerWidget {
  final String userId;
  final List<WorkspaceProfileHeader> profiles;

  const ProfileSelectorScreen({
    super.key,
    required this.userId,
    required this.profiles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final sessionState = ref.watch(profileSessionProvider);
    final activeId = sessionState is ActiveProfileReadySessionState
        ? sessionState.activeProfile.id
        : null;

    return AdaptiveScaffold(
      title: 'Select Workspace',
      actions: [
        if (isIos)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onPressed: () => _handleLogout(context, ref),
          )
        else
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
            tooltip: 'Sign Out',
            onPressed: () => _handleLogout(context, ref),
          ),
      ],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Workspaces',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a workspace to open, or create an additional one for your account.',
                style: AppTypography.bodySmall.copyWith(color: secondaryText),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: profiles.isEmpty
                    ? _buildEmptyState(context, isDark, isIos)
                    : ListView.separated(
                        itemCount: profiles.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final p = profiles[index];
                          final isActive = p.id == activeId;
                          return _buildProfileItem(
                            context: context,
                            profile: p,
                            isActive: isActive,
                            isDark: isDark,
                            isIos: isIos,
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              ref
                                  .read(profileSessionProvider.notifier)
                                  .switchProfile(p);

                              Navigator.of(context).pushAndRemoveUntil(
                                createAdaptivePageRoute(
                                  builder: (_) => const AppRootGate(),
                                  transitionType: SharedAxisTransitionType.scaled,
                                ),
                                (route) => false,
                              );
                            },
                          );
                        },
                      ),
              ),

              const SizedBox(height: 16),
              AdaptiveButton(
                type: AdaptiveButtonType.secondary,
                isFullWidth: true,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (_) => ProfileOnboardingScreen(userId: userId),
                      transitionType: SharedAxisTransitionType.horizontal,
                    ),
                  );
                },
                child: const Text('+ Create New Workspace'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    await ref.read(authControllerProvider.notifier).logout();
    ref.read(profileSessionProvider.notifier).logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(
          builder: (_) => const AppRootGate(),
          transitionType: SharedAxisTransitionType.scaled,
        ),
        (route) => false,
      );
    }
  }

  Widget _buildEmptyState(BuildContext context, bool isDark, bool isIos) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryBlueLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.workspaces_outline,
              size: 32,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No workspaces found',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Set up your first Personal Expense or Business Ledger workspace.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileItem({
    required BuildContext context,
    required WorkspaceProfileHeader profile,
    required bool isActive,
    required bool isDark,
    required bool isIos,
    required VoidCallback onTap,
  }) {
    final isExpense = profile.isExpense;
    final accentColor =
        isExpense ? AppColors.primaryGreen : AppColors.primaryBlue;

    final itemContent = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isExpense
                ? (isIos
                    ? CupertinoIcons.money_dollar_circle
                    : Icons.account_balance_wallet_outlined)
                : (isIos
                    ? CupertinoIcons.building_2_fill
                    : Icons.business_outlined),
            color: accentColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.name,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isActive)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isExpense ? 'EXPENSE' : 'LEDGER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Role: ${profile.role.displayName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  if (profile.currencyCode.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '• ${profile.currencyCode}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
          size: 16,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ],
    );

    if (isIos) {
      return GestureDetector(
        onTap: onTap,
        child: LiquidGlassCard(
          borderRadius: 18,
          borderColor: isActive
              ? AppColors.primaryGreen
              : (isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08)),
          padding: const EdgeInsets.all(14),
          child: itemContent,
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isActive
              ? AppColors.primaryGreen
              : (isDark
                  ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
          width: isActive ? 1.8 : 1.0,
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: itemContent,
        ),
      ),
    );
  }
}
