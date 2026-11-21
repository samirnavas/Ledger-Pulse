import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_bottom_nav.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/spring_morphing_fab.dart';
import '../../data/models/party_model.dart';
import '../../data/models/sync_model.dart';
import '../ledger/ledger_workspace_views.dart';
import '../profile/profile_screen.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/sync_providers.dart';
import '../reports/reporting_hub_screen.dart';
import '../widgets/active_profile_indicator_pill.dart';
import '../widgets/account_header_button.dart';
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

  void setTab(int index) => state = index.clamp(0, 2);
}

final dashboardTabProvider = NotifierProvider<DashboardTabNotifier, int>(
  DashboardTabNotifier.new,
);

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _fabExtended = [true, true];

  static const _labels = ['Parties', 'Transactions', 'Reports'];
  static const _material = [
    Icons.people_outline,
    Icons.receipt_long_outlined,
    Icons.bar_chart_outlined,
  ];
  static const _cupertino = [
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

  bool _handleScroll(int tab, UserScrollNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.direction != ScrollDirection.idle) {
      final extended = notification.direction == ScrollDirection.forward;
      if (_fabExtended[tab] != extended) {
        setState(() => _fabExtended[tab] = extended);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(userCompaniesProvider).isEmpty) {
      return const CreateCompanyFlow(isOnboarding: true);
    }

    ref.watch(autoSyncProvider);
    final sync = ref.watch(syncControllerProvider);
    final companyId = ref.watch(activeCompanyIdProvider);
    final selected = ref.watch(dashboardTabProvider);
    final searchingParties =
        selected == 0 &&
        (ref.watch(isPartySearchActiveProvider) ||
            ref.watch(partySearchQueryProvider).isNotEmpty);
    final isIos = AdaptiveThemeHelper.isIos(context);
    void addParty() => _addParty(context, ref);
    void addTransaction() =>
        openLedgerTransaction(context, ref, onAddParty: addParty);

    void select(int tab) {
      FocusManager.instance.primaryFocus?.unfocus();
      HapticFeedback.selectionClick();
      ref.read(dashboardTabProvider.notifier).setTab(tab);
    }

    Widget fab(int tab) => SpringMorphingFab(
      key: ValueKey(
        tab == 0 ? 'ledger_add_party_fab' : 'ledger_add_transaction_fab',
      ),
      icon: isIos ? CupertinoIcons.add : Icons.add,
      label: tab == 0 ? 'Add Party' : 'Add Transaction',
      isExtended: _fabExtended[tab],
      onPressed: tab == 0 ? addParty : addTransaction,
    );

    Widget scrollableTab(int tab, Widget body) {
      final content = NotificationListener<UserScrollNotification>(
        onNotification: (notification) => _handleScroll(tab, notification),
        child: body,
      );
      if (!isIos) return content;
      return Stack(
        children: [
          content,
          PositionedDirectional(end: 16, bottom: 16, child: fab(tab)),
        ],
      );
    }

    return PopScope(
      canPop: selected == 0 && !searchingParties,
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
        drawer: DashboardSidebarDrawer(
          onOpenArchivedParties: () => showArchivedLedgerParties(context, ref),
        ),
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
          AccountHeaderButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                createAdaptivePageRoute(
                  builder: (_) => const ProfileScreen(isStandalone: true),
                ),
              );
            },
          ),
        ],
        floatingActionButton: !isIos && selected < 2 ? fab(selected) : null,
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
                  scrollableTab(
                    0,
                    Column(
                      children: [
                        const LedgerBalanceCard(),
                        const LedgerPartyFilters(),
                        const Expanded(child: PartyListTab(bottomPadding: 88)),
                      ],
                    ),
                  ),
                  scrollableTab(1, const LedgerTransactionsView()),
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
