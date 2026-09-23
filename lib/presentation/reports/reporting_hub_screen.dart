import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/reporting/gstr_json_engine.dart';
import '../../data/reporting/report_models.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';
import '../providers/reporting_providers.dart';
import '../providers/voucher_providers.dart';
import 'desktop_custom_report_studio.dart';
import 'statement_preview_screen.dart';

class ReportingHubScreen extends ConsumerStatefulWidget {
  const ReportingHubScreen({super.key});

  @override
  ConsumerState<ReportingHubScreen> createState() => _ReportingHubScreenState();
}

class _ReportingHubScreenState extends ConsumerState<ReportingHubScreen> {
  String _searchQuery = '';
  ReportCategory? _selectedCategory;

  Future<void> _exportGstrJson(BuildContext context, ReportMetadata report) async {
    HapticFeedback.lightImpact();
    final company = ref.read(activeCompanyProvider);
    final vouchers = await ref.read(vouchersListProvider(null).future);
    final parties = await ref.read(partyListProvider.future);

    Map<String, dynamic> jsonPayload;
    String filePrefix;

    if (report.id == 'rpt_gstr1') {
      jsonPayload = GstrJsonEngine.generateGstr1Json(
        company: company,
        salesVouchers: vouchers,
        parties: parties,
        returnPeriod: '092026',
      );
      filePrefix = 'GSTR1_Returns';
    } else if (report.id == 'rpt_gstr2') {
      jsonPayload = GstrJsonEngine.generateGstr2Json(
        company: company,
        purchaseVouchers: vouchers,
        parties: parties,
        returnPeriod: '092026',
      );
      filePrefix = 'GSTR2_Inward';
    } else if (report.id == 'rpt_gstr3b') {
      jsonPayload = GstrJsonEngine.generateGstr3bJson(
        company: company,
        salesVouchers: vouchers,
        purchaseVouchers: vouchers,
        returnPeriod: '092026',
      );
      filePrefix = 'GSTR3B_Monthly';
    } else if (report.id == 'rpt_gstr4') {
      jsonPayload = GstrJsonEngine.generateGstr4Json(
        company: company,
        vouchers: vouchers,
        financialYear: '2026-27',
      );
      filePrefix = 'GSTR4_Composition';
    } else if (report.id == 'rpt_gstr9') {
      jsonPayload = GstrJsonEngine.generateGstr9Json(
        company: company,
        salesVouchers: vouchers,
        purchaseVouchers: vouchers,
        financialYear: '2026-27',
      );
      filePrefix = 'GSTR9_Annual';
    } else {
      jsonPayload = GstrJsonEngine.generateGstr2aReconciliationJson(
        booksPurchases: vouchers,
        portal2aFeed: [],
      );
      filePrefix = 'GSTR2A_Reconciliation';
    }

    final formattedJson = GstrJsonEngine.formatJson(jsonPayload);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${filePrefix}_${company.gstin ?? "GSTN"}.json');
    await file.writeAsString(formattedJson);

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${report.title} JSON'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generated JSON formatted strictly for Indian GST Portal upload:'),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade200,
                child: SingleChildScrollView(
                  child: Text(formattedJson, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Share / Save JSON'),
              onPressed: () {
                Navigator.pop(ctx);
                // ignore: deprecated_member_use
                Share.shareXFiles([XFile(file.path, mimeType: 'application/json')]);
              },
            ),
          ],
        ),
      );
    }
  }

  void _openReport(BuildContext context, ReportMetadata report) {
    HapticFeedback.lightImpact();

    if (report.category == ReportCategory.gstCompliance) {
      _exportGstrJson(context, report);
      return;
    }

    if (report.category == ReportCategory.customSql || report.isCustomSql) {
      Navigator.of(context).push(
        createAdaptivePageRoute(builder: (ctx) => const DesktopCustomReportStudio()),
      );
      return;
    }

    Navigator.of(context).push(
      createAdaptivePageRoute(
        builder: (ctx) => StatementPreviewScreen(
          partyId: '',
          reportId: report.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allReports = ref.watch(reportCatalogProvider);

    final filteredReports = allReports.where((r) {
      final matchesCat = _selectedCategory == null || r.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          r.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();

    return AdaptiveScaffold(
      title: 'Reporting & Analytics Hub',
      actions: [
        IconButton(
          tooltip: 'Custom SQL Studio',
          icon: Icon(
            isIos ? CupertinoIcons.chevron_left_slash_chevron_right : Icons.terminal_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () {
            Navigator.of(context).push(
              createAdaptivePageRoute(builder: (ctx) => const DesktopCustomReportStudio()),
            );
          },
        ),
      ],
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search across 35+ financial & statutory reports...',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          // 2. Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Reports (36)'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 8),
                ...ReportCategory.values.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat.displayName),
                      selected: _selectedCategory == cat,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),

          // 3. Reports List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredReports.length,
              itemBuilder: (context, index) {
                final report = filteredReports[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildReportCard(context, report, isIos, isDark),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(BuildContext context, ReportMetadata report, bool isIos, bool isDark) {
    final cardContent = InkWell(
      onTap: () => _openReport(context, report),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getIconData(report.iconCode),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          report.category.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              isIos ? CupertinoIcons.chevron_forward : Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 18,
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7),
        borderColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
        child: cardContent,
      );
    } else {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: Theme.of(context).colorScheme.surface,
        child: cardContent,
      );
    }
  }

  IconData _getIconData(String code) {
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
