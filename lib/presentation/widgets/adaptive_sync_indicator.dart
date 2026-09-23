import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/sync_model.dart';
import '../providers/sync_providers.dart';

class AdaptiveSyncIndicator extends ConsumerWidget {
  final VoidCallback? onTap;

  const AdaptiveSyncIndicator({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final syncStatus = ref.watch(syncControllerProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider).value ?? 0;

    final String statusText;
    if (syncStatus == SyncStatus.syncing) {
      statusText = 'Syncing...';
    } else if (pendingCount > 0) {
      statusText = '$pendingCount pending';
    } else if (syncStatus == SyncStatus.error) {
      statusText = 'Sync error';
    } else {
      statusText = 'Up to date';
    }

    if (isIos) {
      // iOS: Exclusively use LiquidGlassCard and Cupertino components
      return GestureDetector(
        onTap: onTap,
        child: LiquidGlassCard(
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (syncStatus == SyncStatus.syncing)
                const CupertinoActivityIndicator(radius: 6)
              else
                Icon(
                  syncStatus == SyncStatus.error
                      ? CupertinoIcons.exclamationmark_triangle_fill
                      : pendingCount > 0
                          ? CupertinoIcons.arrow_2_circlepath_circle
                          : CupertinoIcons.checkmark_alt_circle_fill,
                  size: 14,
                  color: syncStatus == SyncStatus.error
                      ? CupertinoColors.destructiveRed
                      : pendingCount > 0
                          ? CupertinoColors.activeOrange
                          : CupertinoColors.activeGreen,
                ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Android/Desktop: Material Design 3 Expressive styling
    final colorScheme = Theme.of(context).colorScheme;
    final Color badgeBg = syncStatus == SyncStatus.syncing
        ? colorScheme.primaryContainer
        : syncStatus == SyncStatus.error
            ? colorScheme.errorContainer
            : pendingCount > 0
                ? colorScheme.tertiaryContainer
                : colorScheme.surfaceContainerHighest;

    final Color badgeFg = syncStatus == SyncStatus.syncing
        ? colorScheme.onPrimaryContainer
        : syncStatus == SyncStatus.error
            ? colorScheme.onErrorContainer
            : pendingCount > 0
                ? colorScheme.onTertiaryContainer
                : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: badgeFg.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncStatus == SyncStatus.syncing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: badgeFg,
                ),
              )
            else
              Icon(
                syncStatus == SyncStatus.error
                    ? Icons.warning_amber_rounded
                    : pendingCount > 0
                        ? Icons.cloud_upload_outlined
                        : Icons.check_circle_outline_rounded,
                size: 14,
                color: badgeFg,
              ),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: badgeFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
