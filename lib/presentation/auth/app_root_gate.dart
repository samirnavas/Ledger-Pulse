import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../home/home_shell.dart';
import '../providers/auth_providers.dart';
import '../providers/profile_session_controller.dart';
import '../providers/profile_session_state.dart';
import 'phone_input_screen.dart';
import 'profile_onboarding_screen.dart';
import 'profile_selector_screen.dart';

/// Central reactive session gate that routes the application based on [ProfileSessionState].
///
/// Ensures strict adherence to the profile lifecycle:
/// 1. Unauthenticated -> PhoneInputScreen
/// 2. Loading -> Adaptive loading surface
/// 3. Zero profiles -> ProfileOnboardingScreen (never creates profile implicitly)
/// 4. Multiple profiles -> ProfileSelectorScreen
/// 5. Active Profile ready -> HomeShell
/// 6. Revoked membership / Error -> Adaptive error state with Retry / Switch / Logout
class AppRootGate extends ConsumerWidget {
  const AppRootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(profileSessionProvider);

    if (sessionState is SessionInitializingState ||
        sessionState is LoadingProfilesSessionState) {
      return _buildLoadingScreen(context);
    }

    if (sessionState is UnauthenticatedSessionState) {
      return const PhoneInputScreen();
    }

    if (sessionState is OnboardingRequiredSessionState) {
      return ProfileOnboardingScreen(userId: sessionState.userId);
    }

    if (sessionState is ProfileSelectionRequiredSessionState) {
      return ProfileSelectorScreen(
        userId: sessionState.userId,
        profiles: sessionState.profiles,
      );
    }

    if (sessionState is ActiveProfileReadySessionState) {
      return HomeShell(
        key: ValueKey('active_profile_${sessionState.activeProfile.id}'),
      );
    }

    if (sessionState is SessionErrorState) {
      return _buildErrorScreen(context, ref, sessionState);
    }

    return const PhoneInputScreen();
  }

  Widget _buildLoadingScreen(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final backgroundColor = isIos
        ? (isDark ? AppColors.surfaceDark : AppColors.cupertinoSystemBackground)
        : (isDark
            ? Theme.of(context).colorScheme.surface
            : AppColors.surfaceLight);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryBlueLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 36,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading your workspaces...',
              style: AppTypography.titleSmall.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 16),
            isIos
                ? const CupertinoActivityIndicator(radius: 12)
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(
    BuildContext context,
    WidgetRef ref,
    SessionErrorState errorState,
  ) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final isRevoked = errorState.message.toLowerCase().contains('revoked');

    final title = isRevoked ? 'Access Revoked' : 'Workspace Error';
    final description = isRevoked
        ? 'Your access to the active workspace has been revoked. Please choose an authorized workspace or sign in with another account.'
        : errorState.message;

    return AdaptiveScaffold(
      title: title,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: isIos
                  ? LiquidGlassCard(
                      borderRadius: 24,
                      padding: const EdgeInsets.all(24),
                      child: _buildErrorContent(
                        context,
                        ref,
                        title,
                        description,
                        isRevoked,
                        isDark,
                      ),
                    )
                  : Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: _buildErrorContent(
                          context,
                          ref,
                          title,
                          description,
                          isRevoked,
                          isDark,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorContent(
    BuildContext context,
    WidgetRef ref,
    String title,
    String description,
    bool isRevoked,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: Colors.red,
            size: 32,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: AppTypography.bodySmall.copyWith(
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        AdaptiveButton(
          onPressed: () {
            ref.read(profileSessionProvider.notifier).retry();
          },
          isFullWidth: true,
          child: const Text('Retry'),
        ),
        const SizedBox(height: 12),
        AdaptiveButton(
          type: AdaptiveButtonType.secondary,
          isFullWidth: true,
          onPressed: () {
            ref.read(profileSessionProvider.notifier).showProfileSelector();
          },
          child: const Text('Choose Another Workspace'),
        ),
        const SizedBox(height: 12),
        AdaptiveButton(
          type: AdaptiveButtonType.destructive,
          isFullWidth: true,
          onPressed: () async {
            await ref.read(authControllerProvider.notifier).logout();
            ref.read(profileSessionProvider.notifier).logout();
          },
          child: const Text('Log Out'),
        ),
      ],
    );
  }
}
