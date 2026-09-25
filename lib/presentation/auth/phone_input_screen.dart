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
import '../providers/auth_providers.dart';
import 'otp_screen.dart';

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final TextEditingController _phoneController =
      TextEditingController(text: '98765 43210');
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    final rawNumber = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (rawNumber.length != 10) {
      setState(() {
        _errorMessage = 'Please enter a valid 10-digit mobile number';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final inputRow = Row(
      children: [
        // Country Code Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: isIos
                    ? (isDark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.12))
                    : Theme.of(context).colorScheme.outlineVariant.withValues(
                        alpha: isDark ? 0.35 : 0.5),
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
        // Phone Number Input
        Expanded(
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofocus: true,
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
            onSubmitted: (_) => _handleSubmit(),
          ),
        ),
      ],
    );

    return AdaptiveScaffold(
      title: AppStrings.appName,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Branding Icon
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Container(
                    color: AppColors.primaryBlue,
                    child: Icon(
                      isIos
                          ? CupertinoIcons.money_dollar_circle_fill
                          : Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Header Titles
            const Text(
              AppStrings.enterPhoneTitle,
              style: AppTypography.displayMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.enterPhoneSubtitle,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 36),

            // Phone Input Field (Liquid Glass on iOS, M3 Expressive Container on Android)
            isIos
                ? LiquidGlassContainer(
                    borderRadius: 20,
                    blur: 24,
                    borderColor: _errorMessage != null
                        ? AppColors.payableRed
                        : (isDark ? Colors.white.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.15)),
                    child: inputRow,
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _errorMessage != null
                            ? AppColors.payableRed
                            : Theme.of(context).colorScheme.outlineVariant.withValues(
                                alpha: isDark ? 0.35 : 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: inputRow,
                  ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.payableRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Demo Hint Chip
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

            const SizedBox(height: 36),

            // Submit Button
            AdaptiveButton(
              onPressed: _handleSubmit,
              isFullWidth: true,
              height: 52,
              isLoading: authState.isLoading,
              child: const Text(
                AppStrings.getOtpButton,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

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
