import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_list_row.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/app_feedback.dart';
import '../../data/models/account_model.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import 'widgets/wallet_overview.dart';

class ArchivedWalletsScreen extends ConsumerWidget {
  const ArchivedWalletsScreen({super.key, required this.workspaceId});

  final String workspaceId;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    AccountModel wallet,
  ) async {
    final confirmed = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Restore wallet?',
      message:
          '${wallet.name} will return to your active wallets and total balance.',
      confirmLabel: 'Restore',
    );
    if (!confirmed ||
        !context.mounted ||
        ref.read(activeCompanyProvider).id != workspaceId)
      return;
    try {
      await ref
          .read(expenseRepositoryProvider)
          .updateWallet(id: wallet.id, isActive: true);
      if (context.mounted) showAppFeedback(context, 'Wallet restored');
    } catch (_) {
      if (context.mounted)
        showAppFeedback(
          context,
          'Could not restore the wallet.',
          isError: true,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches =
        ref.watch(activeCompanyProvider.select((company) => company.id)) ==
        workspaceId;
    return AdaptiveScaffold(
      title: 'Archived wallets',
      body: !matches
          ? const Center(
              child: Text('Archived wallets unavailable in this workspace.'),
            )
          : ref
                .watch(archivedWalletsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator.adaptive()),
                  error: (_, _) => const Center(
                    child: Text('Could not load archived wallets.'),
                  ),
                  data: (wallets) => wallets.isEmpty
                      ? const Center(child: Text('No archived wallets.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: wallets.length,
                          itemBuilder: (context, index) {
                            final wallet = wallets[index];
                            final kind = WalletKind.of(wallet);
                            return AdaptiveListRow(
                              title: wallet.name,
                              subtitle: 'Tap to restore',
                              leading: Icon(
                                kind.icon(context),
                                color: kind.color(context),
                              ),
                              trailing: const Icon(Icons.restore_rounded),
                              onTap: () => _restore(context, ref, wallet),
                            );
                          },
                        ),
                ),
    );
  }
}
