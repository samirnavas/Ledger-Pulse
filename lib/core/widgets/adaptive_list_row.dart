import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/typography.dart';
import '../theme/adaptive_theme.dart';

/// Platform-adaptive swipe action background builder extracted from [PartyListTab].
class AdaptiveSwipeBackgrounds {
  /// Left-to-right swipe background (typically for Edit/Archive).
  static Widget edit(
    BuildContext context, {
    String label = 'Edit',
    IconData? icon,
    bool? isIos,
  }) {
    final useIos = isIos ?? AdaptiveThemeHelper.isIos(context);

    if (useIos) {
      return Container(
        color: CupertinoColors.systemBlue,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? CupertinoIcons.pencil, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.edit_rounded,
            color: theme.colorScheme.onPrimaryContainer,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Right-to-left swipe background (typically for Delete/Void).
  static Widget delete(
    BuildContext context, {
    String label = 'Delete',
    IconData? icon,
    bool? isIos,
  }) {
    final useIos = isIos ?? AdaptiveThemeHelper.isIos(context);

    if (useIos) {
      return Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon ?? CupertinoIcons.trash, color: Colors.white, size: 22),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            icon ?? Icons.delete_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 22,
          ),
        ],
      ),
    );
  }
}

/// Platform-adaptive list tile primitive matching the exact visuals of the ledger's party tile.
/// - Leading: iOS circle 44 tinted, Android rounded-16 48 primaryContainer.
/// - Title: [AppTypography.titleMedium].
/// - Subtitle: [AppTypography.labelSmall] with `onSurfaceVariant`.
/// - Trailing: widget (e.g. AmountText).
/// - Divider: indented 76, endIndent 16.
class AdaptiveListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? avatarColor;
  final String? initials;
  final bool showDivider;
  final EdgeInsetsGeometry padding;

  const AdaptiveListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.avatarColor,
    this.initials,
    this.showDivider = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  Widget _buildLeading(BuildContext context, bool isIos) {
    if (leading != null) return leading!;

    final theme = Theme.of(context);
    final text = initials ?? (title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '');
    final color = avatarColor ?? theme.colorScheme.primary;

    if (isIos) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: avatarColor != null
            ? avatarColor!.withValues(alpha: 0.18)
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: avatarColor ?? theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final row = InkWell(
      onTap: onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      onLongPress: onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            }
          : null,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            _buildLeading(context, isIos),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: AppTypography.labelSmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );

    if (!showDivider) return row;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Divider(
          height: 1,
          thickness: 0.5,
          indent: 76,
          endIndent: 16,
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: isDark ? 0.2 : 0.35,
          ),
        ),
      ],
    );
  }
}
