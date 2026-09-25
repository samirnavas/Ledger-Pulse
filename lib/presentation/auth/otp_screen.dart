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
import '../home/dashboard_screen.dart';
import '../providers/auth_providers.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phoneNumber;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredOtp => _controllers.map((c) => c.text).join();

  void _autoFillMockOtp() {
    HapticFeedback.lightImpact();
    const mockCode = '123456';
    for (int i = 0; i < 6; i++) {
      _controllers[i].text = mockCode[i];
    }
    _verify();
  }

  void _verify() async {
    final otp = _enteredOtp;
    if (otp.length < 6) return;

    final success =
        await ref.read(authControllerProvider.notifier).verifyOtp(otp);

    if (success && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(
          builder: (context) => const DashboardScreen(),
          transitionType: SharedAxisTransitionType.scaled,
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final authState = ref.watch(authControllerProvider);

    return PopScope(
      canPop: true,
      child: AdaptiveScaffold(
      title: AppStrings.otpScreenTitle,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subheading with phone
            Text(
              'Code sent to ${widget.phoneNumber}',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the 6-digit verification code below to login.',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 32),

            // 6 OTP Box Inputs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (index) {
                final isIos = AdaptiveThemeHelper.isIos(context);
                final isDark = Theme.of(context).brightness == Brightness.dark;

                final textField = TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  autofocus: index == 0,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isIos
                        ? (isDark ? Colors.white : Colors.black)
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && index < 5) {
                      _focusNodes[index + 1].requestFocus();
                    } else if (val.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                    if (_enteredOtp.length == 6) {
                      _verify();
                    }
                  },
                );

                if (isIos) {
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: LiquidGlassContainer(
                      borderRadius: 16,
                      blur: 20,
                      borderColor: _focusNodes[index].hasFocus
                          ? CupertinoColors.activeBlue
                          : (isDark ? Colors.white.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.15)),
                      child: Center(child: textField),
                    ),
                  );
                }

                return SizedBox(
                  width: 48,
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _focusNodes[index].hasFocus
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant.withValues(
                                alpha: isDark ? 0.35 : 0.5),
                        width: _focusNodes[index].hasFocus ? 2.5 : 1.5,
                      ),
                    ),
                    child: Center(child: textField),
                  ),
                );
              }),
            ),

            if (authState.error != null) ...[
              const SizedBox(height: 16),
              Text(
                authState.error!,
                style: const TextStyle(
                  color: AppColors.payableRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Helper button / Auto-fill chip with M3 Expressive pill shape
            GestureDetector(
              onTap: _autoFillMockOtp,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlueLight.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.sparkles : Icons.auto_awesome,
                      size: 18,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '${AppStrings.otpHelper} (Tap to Auto-fill)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: AppColors.primaryBlueDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 36),

            // Verify Button
            AdaptiveButton(
              onPressed: _enteredOtp.length == 6 ? _verify : null,
              isFullWidth: true,
              height: 52,
              isLoading: authState.isLoading,
              child: const Text(
                AppStrings.verifyAndProceed,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Change Phone Number'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
