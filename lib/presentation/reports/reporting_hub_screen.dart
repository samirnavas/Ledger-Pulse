import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/reporting/report_models.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import '../integrations/third_party_import_screen.dart';
import '../ledger/ledger_workspace_views.dart';
import '../providers/reporting_providers.dart';
import 'statement_preview_screen.dart';

class ReportingHubScreen extends ConsumerWidget {
  const ReportingHubScreen({super.key, this.embedded = false});
  final bool embedded;

  void _openReport(BuildContext context, ReportMetadata report) {
    HapticFeedback.lightImpact();

    Navigator.of(context).push(
      createAdaptivePageRoute(
        builder: (ctx) => Material(
          type: MaterialType.transparency,
          child: StatementPreviewScreen(partyId: '', reportId: report.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final company = ref.watch(activeCompanyProvider);
    if (company.isExpense) {
      return AdaptiveScaffold(
        title: 'Reporting & Analytics Hub',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isIos ? CupertinoIcons.lock_circle_fill : Icons.lock_rounded,
                  size: 56,
                  color: isIos
                      ? CupertinoColors.systemOrange
                      : Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reporting Hub Disabled',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The Advanced Reports module is disabled for the active company. You can enable it in company module settings or upgrade your subscription tier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final body = AdaptivePageEntrance(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final report in ref.watch(reportCatalogProvider))
            _buildReportCard(context, report, isIos, isDark),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Party statements'),
            onTap: () => _selectStatement(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Import parties from CSV'),
            onTap: () => Navigator.of(context).push(
              createAdaptivePageRoute(
                builder: (_) => const Material(
                  type: MaterialType.transparency,
                  child: ThirdPartyImportScreen(csvOnly: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return embedded
        ? body
        : AdaptiveScaffold(title: 'Ledger reports', body: body);
  }

  Future<void> _selectStatement(BuildContext context, WidgetRef ref) async {
    final company = ref.read(activeCompanyProvider).id;
    try {
      final parties = await ref.read(ledgerRepositoryProvider).getParties();
      if (!context.mounted || ref.read(activeCompanyProvider).id != company) {
        return;
      }
      final selected = await showLedgerPartyPicker(context, parties);
      if (selected != null &&
          context.mounted &&
          ref.read(activeCompanyProvider).id == company) {
        Navigator.of(context).push(
          createAdaptivePageRoute(
            builder: (_) => Material(
              type: MaterialType.transparency,
              child: StatementPreviewScreen(partyId: selected.id),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not load parties')));
      }
    }
  }

  Widget _buildReportCard(
    BuildContext context,
    ReportMetadata report,
    bool isIos,
    bool isDark,
  ) {
    final cardContent = InkWell(
      onTap: () => _openReport(context, report),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _getIconData(report.iconCode, isIos),
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          report.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          report.category.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    report.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isIos
                  ? CupertinoIcons.chevron_forward
                  : Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 20,
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.7),
        borderColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.06),
        child: cardContent,
      );
    } else {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
          ),
        ),
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: cardContent,
      );
    }
  }

  IconData _getIconData(String code, bool isIos) {
    if (isIos) {
      switch (code) {
        case 'account_balance':
          return CupertinoIcons.building_2_fill;
        case 'trending_up':
          return CupertinoIcons.graph_square_fill;
        case 'balance':
          return CupertinoIcons.slider_horizontal_3;
        case 'file_download':
          return CupertinoIcons.arrow_down_to_line;
        case 'sync_alt':
          return CupertinoIcons.arrow_2_circlepath;
        case 'inventory':
          return CupertinoIcons.cube_box_fill;
        case 'security':
          return CupertinoIcons.shield_fill;
        default:
          return CupertinoIcons.chart_pie_fill;
      }
    }
    switch (code) {
      case 'account_balance':
        return Icons.account_balance_rounded;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'balance':
        return Icons.balance_rounded;
      case 'file_download':
        return Icons.file_download_rounded;
      case 'sync_alt':
        return Icons.sync_alt_rounded;
      case 'inventory':
        return Icons.inventory_2_rounded;
      case 'security':
        return Icons.security_rounded;
      default:
        return Icons.analytics_rounded;
    }
  }
}
