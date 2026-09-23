import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/sync_model.dart';
import '../providers/company_providers.dart';
import '../providers/sync_providers.dart';

class SyncSettingsSheet extends ConsumerWidget {
  final ScrollController scrollController;

  const SyncSettingsSheet({super.key, required this.scrollController});

  static Future<void> show(BuildContext context) {
    return showAdaptiveDraggableModal(
      context: context,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => SyncSettingsSheet(scrollController: scrollCtrl),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final activeCompany = ref.watch(activeCompanyProvider);
    final syncStatus = ref.watch(syncControllerProvider);
    final pendingCountAsync = ref.watch(pendingSyncCountProvider);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Sync & Backup Center',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isIos ? CupertinoColors.label : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: syncStatus == SyncStatus.syncing
                    ? Colors.amber.withValues(alpha: 0.2)
                    : syncStatus == SyncStatus.success
                        ? Colors.green.withValues(alpha: 0.2)
                        : syncStatus == SyncStatus.error
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                syncStatus.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: syncStatus == SyncStatus.syncing
                      ? Colors.amber.shade800
                      : syncStatus == SyncStatus.success
                          ? Colors.green.shade700
                          : syncStatus == SyncStatus.error
                              ? Colors.red.shade700
                              : Colors.blue.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isIos) ...[
          LiquidGlassCard(
            borderRadius: 16,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pending Outbox Queue',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${pendingCountAsync.value ?? 0} mutations',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Supabase Cloud Sync',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Bidirectional real-time PostgreSQL sync',
                            style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel),
                          ),
                        ],
                      ),
                      CupertinoSwitch(
                        value: activeCompany.isCloudSyncEnabled,
                        onChanged: (val) {
                          ref.read(companyControllerProvider.notifier).updateCompanySettings(
                                companyId: activeCompany.id,
                                isCloudSyncEnabled: val,
                                isDropboxSyncEnabled: val ? false : activeCompany.isDropboxSyncEnabled,
                              );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dropbox Encrypted Backup',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Manual snapshot for offline companies',
                            style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel),
                          ),
                        ],
                      ),
                      CupertinoSwitch(
                        value: activeCompany.isDropboxSyncEnabled,
                        onChanged: (val) {
                          ref.read(companyControllerProvider.notifier).updateCompanySettings(
                                companyId: activeCompany.id,
                                isDropboxSyncEnabled: val,
                                isCloudSyncEnabled: val ? false : activeCompany.isCloudSyncEnabled,
                              );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          CupertinoButton.filled(
            onPressed: syncStatus == SyncStatus.syncing
                ? null
                : () async {
                    final res = await ref.read(syncControllerProvider.notifier).triggerSync();
                    if (context.mounted) {
                      showCupertinoDialog(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: Text(res.success ? 'Sync Completed' : 'Sync Notice'),
                          content: Text(res.success
                              ? 'Pushed ${res.itemsPushed} changes, pulled ${res.itemsPulled} updates.'
                              : (res.errorMessage ?? 'Sync encountered an issue.')),
                          actions: [
                            CupertinoDialogAction(
                              child: const Text('OK'),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      );
                    }
                  },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (syncStatus == SyncStatus.syncing) ...[
                  const CupertinoActivityIndicator(color: CupertinoColors.white),
                  const SizedBox(width: 8),
                ] else ...[
                  const Icon(CupertinoIcons.arrow_2_circlepath, size: 20),
                  const SizedBox(width: 8),
                ],
                const Text('Sync Now'),
              ],
            ),
          ),
        ] else ...[
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pending Outbox Queue',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      Chip(
                        label: Text('${pendingCountAsync.value ?? 0} changes'),
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    title: const Text('Supabase Cloud Sync'),
                    subtitle: const Text('Bidirectional PostgreSQL real-time sync'),
                    value: activeCompany.isCloudSyncEnabled,
                    onChanged: (val) {
                      ref.read(companyControllerProvider.notifier).updateCompanySettings(
                            companyId: activeCompany.id,
                            isCloudSyncEnabled: val,
                            isDropboxSyncEnabled: val ? false : activeCompany.isDropboxSyncEnabled,
                          );
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Dropbox Storage Backup'),
                    subtitle: const Text('Manual snapshot backup for local companies'),
                    value: activeCompany.isDropboxSyncEnabled,
                    onChanged: (val) {
                      ref.read(companyControllerProvider.notifier).updateCompanySettings(
                            companyId: activeCompany.id,
                            isDropboxSyncEnabled: val,
                            isCloudSyncEnabled: val ? false : activeCompany.isCloudSyncEnabled,
                          );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: syncStatus == SyncStatus.syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(syncStatus == SyncStatus.syncing ? 'Syncing...' : 'Sync Now'),
            onPressed: syncStatus == SyncStatus.syncing
                ? null
                : () async {
                    final res = await ref.read(syncControllerProvider.notifier).triggerSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res.success
                              ? 'Sync success: ${res.itemsPushed} pushed, ${res.itemsPulled} pulled.'
                              : (res.errorMessage ?? 'Sync failed')),
                          backgroundColor: res.success ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
          ),
        ],
      ],
    );
  }
}
