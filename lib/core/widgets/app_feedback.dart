import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../theme/adaptive_theme.dart';

/// Platform-adaptive feedback notification.
/// - Android: Floating M3 [SnackBar] with themed colors and rounded borders.
/// - iOS: [CupertinoAlertDialog] for errors, or top floating frosted glass banner for standard messages.
void showAppFeedback(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
}) {
  final isIos = AdaptiveThemeHelper.isIos(context);

  if (isIos) {
    if (isError) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Notice'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('OK'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
      return;
    }

    // iOS non-error: try to present a top glass banner; fallback to SnackBar if Overlay is unavailable
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) {
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) => _TopGlassBanner(
          message: message,
          onDismiss: () {
            if (entry.mounted) entry.remove();
          },
        ),
      );
      overlay.insert(entry);
      Future.delayed(duration, () {
        if (entry.mounted) entry.remove();
      });
      return;
    }
  }

  // Material / fallback
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    try {
      final theme = Theme.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: isError
                  ? theme.colorScheme.onError
                  : theme.colorScheme.onInverseSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: isError
              ? theme.colorScheme.error
              : theme.colorScheme.inverseSurface,
          duration: duration,
        ),
      );
    } catch (_) {
      // In case there is no descendant Scaffold in the widget tree (e.g. during body-only tests)
    }
  }
}

class _TopGlassBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _TopGlassBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_TopGlassBanner> createState() => _TopGlassBannerState();
}

class _TopGlassBannerState extends State<_TopGlassBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: LiquidGlassContainer(
                borderRadius: 16,
                blur: 24,
                border: 1.2,
                borderColor: isDark
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 20,
                      color: isDark
                          ? const Color(0xFF4ADE80)
                          : CupertinoColors.activeGreen,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? CupertinoColors.white
                              : CupertinoColors.black,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
