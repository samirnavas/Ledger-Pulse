import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../../../core/theme/adaptive_theme.dart';

/// Custom oversized platform-adaptive numeric keypad (0-9, ., ⌫).
/// On iOS: RealLiquidGlass with Cupertino styling.
/// On Android: Material 3 FilledButton.tonal.
class EntryNumericKeypad extends StatelessWidget {
  final ValueChanged<String> onKeyTap;
  final VoidCallback onLongPressBackspace;
  final Color? themeColor;

  const EntryNumericKeypad({
    super.key,
    required this.onKeyTap,
    required this.onLongPressBackspace,
    this.themeColor,
  });

  Widget _buildKeypadButton({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    IconData? icon,
    bool isAction = false,
  }) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final buttonBg = isDark
        ? (isAction ? const Color(0xFF1C1C1C) : const Color(0xFF242424))
        : (isAction
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainerHigh);
    final buttonFg = isDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final borderColor = isDark
        ? const Color(0xFF333333)
        : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4);

    if (isIos) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          height: 52,
          child: RealLiquidGlass(
            borderRadius: 16,
            glassColor: buttonBg,
            borderColor: borderColor,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
                onLongPress: onLongPress != null
                    ? () {
                        HapticFeedback.mediumImpact();
                        onLongPress();
                      }
                    : null,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: icon != null
                      ? Icon(
                          icon,
                          size: 22,
                          color: buttonFg,
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: label == '.' ? 26 : 24,
                            fontWeight: FontWeight.w700,
                            color: buttonFg,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: SizedBox(
          height: 52,
          child: FilledButton.tonal(
            onPressed: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            onLongPress: onLongPress != null
                ? () {
                    HapticFeedback.mediumImpact();
                    onLongPress();
                  }
                : null,
            style: ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(buttonBg),
              foregroundColor: WidgetStatePropertyAll(buttonFg),
              side: WidgetStatePropertyAll(
                BorderSide(color: borderColor, width: 1),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            child: icon != null
                ? Icon(icon, size: 22, color: buttonFg)
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: label == '.' ? 26 : 24,
                      fontWeight: FontWeight.w700,
                      color: buttonFg,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _buildKeypadButton(
              context: context,
              label: '1',
              onTap: () => onKeyTap('1'),
            ),
            _buildKeypadButton(
              context: context,
              label: '2',
              onTap: () => onKeyTap('2'),
            ),
            _buildKeypadButton(
              context: context,
              label: '3',
              onTap: () => onKeyTap('3'),
            ),
          ],
        ),
        Row(
          children: [
            _buildKeypadButton(
              context: context,
              label: '4',
              onTap: () => onKeyTap('4'),
            ),
            _buildKeypadButton(
              context: context,
              label: '5',
              onTap: () => onKeyTap('5'),
            ),
            _buildKeypadButton(
              context: context,
              label: '6',
              onTap: () => onKeyTap('6'),
            ),
          ],
        ),
        Row(
          children: [
            _buildKeypadButton(
              context: context,
              label: '7',
              onTap: () => onKeyTap('7'),
            ),
            _buildKeypadButton(
              context: context,
              label: '8',
              onTap: () => onKeyTap('8'),
            ),
            _buildKeypadButton(
              context: context,
              label: '9',
              onTap: () => onKeyTap('9'),
            ),
          ],
        ),
        Row(
          children: [
            _buildKeypadButton(
              context: context,
              label: '.',
              onTap: () => onKeyTap('.'),
              isAction: true,
            ),
            _buildKeypadButton(
              context: context,
              label: '0',
              onTap: () => onKeyTap('0'),
            ),
            _buildKeypadButton(
              context: context,
              label: '',
              icon: isIos
                  ? CupertinoIcons.delete_left
                  : Icons.backspace_outlined,
              onTap: () => onKeyTap('backspace'),
              onLongPress: onLongPressBackspace,
              isAction: true,
            ),
          ],
        ),
      ],
    );
  }
}
