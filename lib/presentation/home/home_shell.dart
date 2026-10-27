import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/company_model.dart';
import '../../data/models/party_model.dart';
import '../expense/expense_home_screen.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import 'dashboard_screen.dart';

/// Root shell that dynamically swaps between [DashboardScreen] (for [CompanyMode.ledger])
/// and [ExpenseHomeScreen] (for [CompanyMode.expenseTracker]).
///
/// It listens to [activeCompanyProvider] changes, resets mode-specific state
/// (selected tab, search query, search focus, party filters, and sort order)
/// immediately on company swap, and keeps widget deep links intact.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
    // Reset mode-specific state whenever the active company changes
    ref.listen<Company>(activeCompanyProvider, (previous, next) {
      if (previous != null && (previous.id != next.id || previous.mode != next.mode)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            resetModeSpecificState(ref);
          }
        });
      }
    });

    // Watch mode via select for targeted rebuilds
    final mode = ref.watch(activeCompanyProvider.select((c) => c.mode));
    final activeCompanyId = ref.watch(activeCompanyProvider.select((c) => c.id));

    // Scoped key ensures a pristine widget tree upon switching companies or modes
    final screenKey = ValueKey('home_${activeCompanyId}_${mode.name}');

    switch (mode) {
      case CompanyMode.expenseTracker:
        return ExpenseHomeScreen(key: screenKey);
      case CompanyMode.ledger:
        return DashboardScreen(key: screenKey);
    }
  }

  /// Resets mode-specific state (selected tab, search, filters)
  static void resetModeSpecificState(dynamic ref) {
    // 1. Reset dashboard tab to 0 (default to customers/overview)
    try {
      ref.invalidate(dashboardTabProvider);
    } catch (_) {
      // Ignored if dashboard provider container is unmounted
    }

    // 2. Reset search query and search focus state
    try {
      ref.read(partySearchQueryProvider.notifier).setQuery('');
      ref.read(isPartySearchActiveProvider.notifier).setActive(false);
    } catch (_) {
      // Ignored if search providers are unmounted
    }

    // 3. Reset party filters & sorting
    try {
      ref.read(selectedPartyTypeFilterProvider.notifier).setFilter(PartyType.customer);
      ref.read(partySortOptionProvider.notifier).setSort(PartySortOption.mostRecent);
    } catch (_) {
      // Ignored if filter providers are unmounted
    }
  }
}
