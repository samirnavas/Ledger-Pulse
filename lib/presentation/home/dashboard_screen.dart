import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../data/models/party_model.dart';
import '../../data/models/sync_model.dart';
import '../ledger/ledger_workspace_views.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/sync_providers.dart';
import '../reports/reporting_hub_screen.dart';
import '../widgets/active_profile_indicator_pill.dart';
import 'add_party_dialog.dart';
import 'create_company_flow.dart';
import 'dashboard_sidebar_drawer.dart';
import 'party_list_tab.dart';
import 'sync_settings_sheet.dart';

class DashboardTabNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(activeCompanyIdProvider);
    return 0;
  }

  void setTab(int index) => state = index.clamp(0, 3);
}

final dashboardTabProvider = NotifierProvider<DashboardTabNotifier, int>(
  DashboardTabNotifier.new,
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const _labels = ['Home', 'Parties', 'Transactions', 'Reports'];
  static const _material = [
    Icons.home_outlined,
    Icons.people_outline,
    Icons.receipt_long_outlined,
    Icons.bar_chart_outlined,
  ];
  static const _cupertino = [
    CupertinoIcons.house,
    CupertinoIcons.person_2,
    CupertinoIcons.list_bullet,
    CupertinoIcons.chart_bar,
  ];

  void _addParty(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddPartyDialog(
        initialType:
            ref.read(selectedPartyTypeFilterProvider) ?? PartyType.customer,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(userCompaniesProvider).isEmpty) {
      return const CreateCompanyFlow(isOnboarding: true);
    }

    ref.watch(autoSyncProvider);
    final sync = ref.watch(syncControllerProvider);
    final companyId = ref.watch(activeCompanyIdProvider);
    final selected = ref.watch(dashboardTabProvider);
    final searchingParties = selected == 1 &&
        (ref.watch(isPartySearchActiveProvider) ||
            ref.watch(partySearchQueryProvider).isNotEmpty);
    final isIos = AdaptiveThemeHelper.isIos(context);
    final canAdd = selected != 3;
    void add() {
      if (selected == 1) {
        _addParty(context, ref);
      } else {
        openLedgerTransaction(
          context,
          ref,
          onAddParty: () => _addParty(context, ref),
        );
      }
    }

    void select(int tab) {
      FocusManager.instance.primaryFocus?.unfocus();
      HapticFeedback.selectionClick();
      ref.read(dashboardTabProvider.notifier).setTab(tab);
    }

    return PopScope(
      canPop: selected == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (searchingParties) {
          FocusManager.instance.primaryFocus?.unfocus();
          ref.read(partySearchQueryProvider.notifier).setQuery('');
          ref.read(isPartySearchActiveProvider.notifier).setActive(false);
        } else if (selected != 0) {
          select(0);
        }
      },
      child: AdaptiveScaffold(
        drawer: const DashboardSidebarDrawer(),
        titleWidget: const Material(
          type: MaterialType.transparency,
          child: ActiveProfileIndicatorPill(),
        ),
        actions: [
          if (isIos)
            Semantics(
              label: 'Sync & Backup',
              button: true,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => SyncSettingsSheet.show(context),
                child: sync == SyncStatus.syncing
                    ? const CupertinoActivityIndicator(radius: 9)
                    : const Icon(CupertinoIcons.cloud_upload, size: 22),
              ),
            )
          else
            IconButton(
              tooltip: 'Sync & Backup',
              onPressed: () => SyncSettingsSheet.show(context),
              icon: sync == SyncStatus.syncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isIos
                          ? CupertinoIcons.cloud_upload
                          : Icons.cloud_sync_outlined,
                    ),
            ),
          if (isIos && canAdd)
            Semantics(
              label: selected == 1 ? 'Add party' : 'Add transaction',
              button: true,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: add,
                child: const Icon(CupertinoIcons.add, size: 22),
              ),
            ),
        ],
        floatingActionButton: !isIos && canAdd
            ? FloatingActionButton(
                tooltip: selected == 1 ? 'Add party' : 'Add transaction',
                onPressed: add,
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: AdaptiveBottomNav(
          currentIndex: selected,
          onTap: select,
          destinations: [
            for (var i = 0; i < _labels.length; i++)
              NavigationDestination(
                icon: Icon(_material[i]),
                label: _labels[i],
              ),
          ],
          iosItems: [
            for (var i = 0; i < _labels.length; i++)
              BottomNavigationBarItem(
                icon: Icon(_cupertino[i]),
                label: _labels[i],
              ),
          ],
        ),
        body: Column(
          children: [
            if (sync == SyncStatus.error || sync == SyncStatus.partial)
              ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text(
                  'Sync unavailable. Your changes are saved here.',
                ),
                onTap: () => SyncSettingsSheet.show(context),
              ),
            Expanded(
              child: IndexedStack(
                key: ValueKey(companyId),
                index: selected,
                children: [
                  LedgerHomeView(
                    onAddParty: () => _addParty(context, ref),
                    onAddTransaction: () => openLedgerTransaction(
                      context,
                      ref,
                      onAddParty: () => _addParty(context, ref),
                    ),
                    onViewTransactions: () => select(2),
                  ),
                  Column(
                    children: [
                      const LedgerPartyFilters(),
                      const Expanded(child: PartyListTab()),
                    ],
                  ),
                  const LedgerTransactionsView(),
                  const ReportingHubScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
