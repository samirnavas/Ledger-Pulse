import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';

/// Platform-adaptive search input field.
/// - iOS: [LiquidGlassContainer] height 44, radius 14 with [CupertinoIcons.search] and clear button.
/// - Android: M3 [SearchBar] height 48, radius 24 with outline variant border.
class AdaptiveSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final EdgeInsetsGeometry? padding;

  const AdaptiveSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Search...',
    this.onChanged,
    this.onClear,
    this.padding,
  });

  @override
  State<AdaptiveSearchField> createState() => _AdaptiveSearchFieldState();
}

class _AdaptiveSearchFieldState extends State<AdaptiveSearchField> {
  TextEditingController? _internalController;
  TextEditingController get _effectiveController =>
      widget.controller ?? (_internalController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _effectiveController.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AdaptiveSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)?.removeListener(_onControllerChanged);
      _effectiveController.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_onControllerChanged);
    _internalController?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _effectiveController.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _effectiveController.text.isNotEmpty;

    final content = isIos
        ? LiquidGlassContainer(
            height: 44,
            borderRadius: 14,
            blur: 20,
            border: 1.2,
            borderColor: isDark
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  size: 18,
                  color: AppColors.textMutedLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _effectiveController,
                    focusNode: widget.focusNode,
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    onChanged: widget.onChanged,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textMutedLight,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                if (hasText)
                  GestureDetector(
                    onTap: _clearSearch,
                    child: const Icon(
                      CupertinoIcons.clear_circled_solid,
                      size: 16,
                      color: AppColors.textMutedLight,
                    ),
                  ),
              ],
            ),
          )
        : SearchBar(
            controller: _effectiveController,
            focusNode: widget.focusNode,
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
              Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            side: WidgetStatePropertyAll(
              BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.6),
                width: 1.0,
              ),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.6),
                  width: 1.0,
                ),
              ),
            ),
            leading: const Icon(Icons.search),
            hintText: widget.hint,
            hintStyle: WidgetStatePropertyAll(
              TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: [
              if (hasText)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSearch,
                ),
            ],
            onChanged: widget.onChanged,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            constraints: const BoxConstraints(
              minHeight: 48,
              maxHeight: 48,
            ),
          );

    if (widget.padding != null) {
      return Padding(padding: widget.padding!, child: content);
    }
    return content;
  }
}
