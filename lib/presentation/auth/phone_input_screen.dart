import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../providers/auth_providers.dart';
import '../providers/profile_session_controller.dart';
import 'app_root_gate.dart';
import 'otp_screen.dart';

enum AuthMode { phoneOtp, emailPassword }
enum EmailAuthType { signIn, signUp }

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  AuthMode _authMode = AuthMode.phoneOtp;
  EmailAuthType _emailAuthType = EmailAuthType.signUp;
  bool _isCompanyAccount = true; // default: Company account (Business Ledger)
  bool _obscurePassword = true;
  bool _isBootstrapping = false;

  final TextEditingController _phoneController =
      TextEditingController(text: '98765 43210');
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handlePhoneOtpSubmit() async {
    final rawNumber = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (rawNumber.length != 10) {
      setState(() {
        _errorMessage = 'Please enter a valid 10-digit mobile number';
      });
      return;
    }

    setState(() => _errorMessage = null);

    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp('+91 $rawNumber');

    if (success && mounted) {
      Navigator.of(context).push(
        createAdaptivePageRoute(
          builder: (context) => OtpScreen(phoneNumber: '+91 $rawNumber'),
          transitionType: SharedAxisTransitionType.horizontal,
        ),
      );
    }
  }

  void _handleEmailSubmit() async {
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
      if (_emailAuthType == EmailAuthType.signUp) {
        if (name.isEmpty) {
          setState(() {
            _errorMessage = _isCompanyAccount
                ? 'Please enter your business or company name'
                : 'Please enter your full name';
            _isBootstrapping = false;
          });
          return;
        }

        final success = await ref
            .read(authControllerProvider.notifier)
            .signUpWithEmailAndPassword(
              email: email,
              password: password,
              name: name,
              isCompanyAccount: _isCompanyAccount,
            );

        if (success && mounted) {
          await ref
              .read(profileSessionProvider.notifier)
              .loadProfilesForUser(email);

          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              createAdaptivePageRoute(
                builder: (context) => const AppRootGate(),
                transitionType: SharedAxisTransitionType.scaled,
              ),
              (route) => false,
            );
          }
        } else if (!success && mounted) {
          final err = ref.read(authControllerProvider).error;
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
          await ref
              .read(profileSessionProvider.notifier)
              .loadProfilesForUser(email);

          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              createAdaptivePageRoute(
                builder: (context) => const AppRootGate(),
                transitionType: SharedAxisTransitionType.scaled,
              ),
              (route) => false,
            );
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final phoneInputRow = Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: isIos
                    ? (isDark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.12))
                    : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🇮🇳', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                AppStrings.countryCode,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isIos
                      ? (isDark ? Colors.white : Colors.black)
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofocus: false,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: isIos
                  ? (isDark ? Colors.white : Colors.black)
                  : Theme.of(context).colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              hintText: AppStrings.phonePlaceholder,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              fillColor: Colors.transparent,
            ),
            onSubmitted: (_) => _handlePhoneOtpSubmit(),
          ),
        ),
      ],
    );

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

            // Auth Method Selector (Phone OTP vs Email/Password)
            AdaptiveSegmentedControl<AuthMode>(
              groupValue: _authMode,
              children: const {
                AuthMode.phoneOtp: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_android_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Phone OTP'),
                  ],
                ),
                AuthMode.emailPassword: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.email_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Email & Password'),
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

            if (_authMode == AuthMode.phoneOtp) ...[
              const Text(
                AppStrings.enterPhoneTitle,
                style: AppTypography.displayMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.enterPhoneSubtitle,
                style: AppTypography.bodyMedium,
              ),
              const SizedBox(height: 24),

              isIos
                  ? LiquidGlassContainer(
                      borderRadius: 20,
                      blur: 24,
                      borderColor: _errorMessage != null
                          ? AppColors.payableRed
                          : (isDark ? Colors.white.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.15)),
                      child: phoneInputRow,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _errorMessage != null
                              ? AppColors.payableRed
                              : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: phoneInputRow,
                    ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.payableRed, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],

              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _phoneController.text = '98765 43210';
                  setState(() => _errorMessage = null);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isIos ? CupertinoIcons.bolt_fill : Icons.bolt,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Use demo: 98765 43210',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
              AdaptiveButton(
                onPressed: _handlePhoneOtpSubmit,
                isFullWidth: true,
                height: 52,
                isLoading: authState.isLoading,
                child: const Text(
                  AppStrings.getOtpButton,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ] else ...[
              // EMAIL & PASSWORD MODE
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _emailAuthType == EmailAuthType.signIn ? 'Sign In' : 'Create Account',
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
                          _emailAuthType = _emailAuthType == EmailAuthType.signIn
                              ? EmailAuthType.signUp
                              : EmailAuthType.signIn;
                          _errorMessage = null;
                        });
                      },
                      child: Text(
                        _emailAuthType == EmailAuthType.signIn
                            ? 'Need an account? Sign Up'
                            : 'Already have an account? Sign In',
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
              const SizedBox(height: 16),

              if (_emailAuthType == EmailAuthType.signUp) ...[
                // ACCOUNT TYPE SELECTOR (Personal vs Company)
                Text(
                  'Profile Type:',
                  style: AppTypography.labelLarge.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 8),
                AdaptiveSegmentedControl<bool>(
                  groupValue: _isCompanyAccount,
                  children: const {
                    true: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Business Ledger'),
                      ],
                    ),
                    false: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wallet_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Expense Tracker'),
                      ],
                    ),
                  },
                  onValueChanged: (val) {
                    HapticFeedback.lightImpact();
                    setState(() => _isCompanyAccount = val);
                  },
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: _isCompanyAccount ? 'Company / Business Name' : 'Your Full Name',
                    hintText: _isCompanyAccount ? 'e.g. Acme Enterprises' : 'e.g. John Doe',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(_isCompanyAccount ? Icons.business_rounded : Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
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
                onSubmitted: (_) => _handleEmailSubmit(),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.payableRed, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],

              const SizedBox(height: 28),
              AdaptiveButton(
                onPressed: _handleEmailSubmit,
                isFullWidth: true,
                height: 52,
                isLoading: authState.isLoading || _isBootstrapping,
                child: Text(
                  _emailAuthType == EmailAuthType.signIn ? 'Sign In' : 'Create Account',
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
