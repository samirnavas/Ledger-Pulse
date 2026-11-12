import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../providers/auth_providers.dart';
import '../providers/profile_session_controller.dart';
import 'app_root_gate.dart';

enum AuthMode { signUp, login }

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  AuthMode _authMode = AuthMode.signUp;
  bool _obscurePassword = true;
  bool _isBootstrapping = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isBootstrapping = true;
    });

    try {
      if (_authMode == AuthMode.signUp) {
        if (name.isEmpty) {
          setState(() {
            _errorMessage = 'Please enter your full name';
            _isBootstrapping = false;
          });
          return;
        }

        final result = await ref
            .read(authControllerProvider.notifier)
            .signUpWithEmailAndPassword(
              email: email,
              password: password,
              name: name,
            );

        if (result.isSuccess) {
          if (result.requiresEmailConfirmation) {
            // Handled reactively by AuthState.isEmailConfirmationPending
            return;
          }

          final userId = ref.read(authControllerProvider).userId ??
              ref.read(authRepositoryProvider).currentUserId;

          if (userId != null && mounted) {
            await ref
                .read(profileSessionProvider.notifier)
                .loadProfilesForUser(userId, isLogin: true);

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                createAdaptivePageRoute(
                  builder: (context) => const AppRootGate(),
                  transitionType: SharedAxisTransitionType.scaled,
                ),
                (route) => false,
              );
            }
          }
        } else if (mounted) {
          final err = ref.read(authControllerProvider).error ?? result.message;
          setState(() => _errorMessage = err ?? 'Failed to create account');
        }
      } else {
        final success = await ref
            .read(authControllerProvider.notifier)
            .signInWithEmailAndPassword(
              email: email,
              password: password,
            );

        if (success && mounted) {
          final userId = ref.read(authControllerProvider).userId ??
              ref.read(authRepositoryProvider).currentUserId;

          if (userId != null && mounted) {
            await ref
                .read(profileSessionProvider.notifier)
                .loadProfilesForUser(userId, isLogin: true);

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                createAdaptivePageRoute(
                  builder: (context) => const AppRootGate(),
                  transitionType: SharedAxisTransitionType.scaled,
                ),
                (route) => false,
              );
            }
          }
        } else if (!success && mounted) {
          final err = ref.read(authControllerProvider).error;
          setState(() => _errorMessage = err ?? 'Sign in failed');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Authentication error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isBootstrapping = false);
      }
    }
  }

  Widget _buildEmailConfirmationPendingView(
    BuildContext context,
    AuthState authState,
    bool isIos,
    bool isDark,
  ) {
    final email = authState.confirmationEmail ?? _emailController.text.trim();
    final primaryColor = isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isIos ? CupertinoIcons.mail_solid : Icons.mark_email_read_rounded,
            color: primaryColor,
            size: 38,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Verify Your Email',
          style: AppTypography.displayMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'We have sent a verification link to:',
          style: AppTypography.bodyMedium.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            email,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isIos ? (isDark ? Colors.white : Colors.black) : Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Please open your email and tap the confirmation link to activate your account. Once verified, return here to sign in.',
          style: AppTypography.bodySmall.copyWith(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        AdaptiveButton(
          onPressed: () {
            ref.read(authControllerProvider.notifier).clearConfirmationPending();
            setState(() {
              _authMode = AuthMode.login;
              _errorMessage = null;
            });
          },
          isFullWidth: true,
          height: 52,
          child: const Text(
            'Proceed to Login',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            ref.read(authControllerProvider.notifier).clearConfirmationPending();
            setState(() {
              _authMode = AuthMode.signUp;
              _errorMessage = null;
            });
          },
          child: Text(
            'Use a different email address',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
        ),
      ],
    );

    return isIos
        ? LiquidGlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            child: content,
          )
        : Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: content,
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      title: AppStrings.appName,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Branding Header
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => Container(
                        color: AppColors.primaryBlue,
                        child: Icon(
                          isIos ? CupertinoIcons.money_dollar_circle_fill : Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AppStrings.appName,
                      style: AppTypography.titleLarge,
                    ),
                    Text(
                      'Secure Cloud Accounting & Sync',
                      style: AppTypography.bodySmall.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Sign Up / Login Switcher
            AdaptiveSegmentedControl<AuthMode>(
              groupValue: _authMode,
              children: const {
                AuthMode.signUp: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_add_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Sign Up'),
                  ],
                ),
                AuthMode.login: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Login'),
                  ],
                ),
              },
              onValueChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() {
                  _authMode = val;
                  _errorMessage = null;
                });
              },
            ),
            const SizedBox(height: 24),

            if (authState.isEmailConfirmationPending) ...[
              // EMAIL CONFIRMATION PENDING STATE
              _buildEmailConfirmationPendingView(context, authState, isIos, isDark),
            ] else ...[
              // SIGN UP / LOGIN FORM
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _authMode == AuthMode.signUp ? 'Create Account' : 'Login',
                    style: AppTypography.displayMedium,
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _authMode = _authMode == AuthMode.login
                              ? AuthMode.signUp
                              : AuthMode.login;
                          _errorMessage = null;
                        });
                      },
                      child: Text(
                        _authMode == AuthMode.login
                            ? 'Need an account? Sign Up'
                            : 'Already have an account? Login',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_authMode == AuthMode.signUp) ...[
                // PERSONAL DETAILS ONLY: FULL NAME
                TextField(
                  key: const Key('signup_name_field'),
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'e.g. John Doe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                key: const Key('auth_email_field'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'name@example.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                key: const Key('auth_password_field'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'At least 6 characters',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  ),
                ),
                onSubmitted: (_) => _handleSubmit(),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppColors.payableRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 28),
              AdaptiveButton(
                onPressed: _handleSubmit,
                isFullWidth: true,
                height: 52,
                isLoading: authState.isLoading || _isBootstrapping,
                child: Text(
                  _authMode == AuthMode.login ? 'Login' : 'Create Account',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Center(
              child: Text(
                'By continuing, you agree to the Terms of Service & Privacy Policy',
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
