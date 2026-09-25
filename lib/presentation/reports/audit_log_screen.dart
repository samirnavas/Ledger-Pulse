import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/local/drift_ledger_repository.dart';
import '../../data/models/audit_log_model.dart';
import '../providers/company_providers.dart';
import '../providers/ledger_providers.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  bool _isLoading = true;
  bool? _isChainValid;
  List<AuditLog> _logs = [];
  String? _filterEntityType;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final repo = ref.read(ledgerRepositoryProvider);
    if (repo is DriftLedgerRepository) {
      final activeCompany = ref.read(activeCompanyProvider);
      final logs = await repo.auditService.getAuditLogs(
        companyId: activeCompany.id,
        entityType: _filterEntityType,
      );
      final valid = await repo.auditService.verifyChainIntegrity(activeCompany.id);
      if (mounted) {
        setState(() {
          _logs = logs;
          _isChainValid = valid;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _logs = [];
          _isChainValid = true;
          _isLoading = false;
        });
      }
    }
  }

  Color _getActionColor(AuditAction action) {
    switch (action) {
      case AuditAction.insert:
        return Colors.green;
      case AuditAction.update:
        return Colors.blue;
      case AuditAction.delete:
        return Colors.red;
      case AuditAction.voided:
        return Colors.deepOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final activeCompany = ref.watch(activeCompanyProvider);

    return AdaptiveScaffold(
      title: 'Statutory Audit Trail',
      actions: [
        if (isIos)
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _loadLogs,
            child: const Icon(CupertinoIcons.arrow_clockwise),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadLogs,
          ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator.adaptive(
              onRefresh: _loadLogs,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // Tamper-Evident Verification Banner
                  if (isIos)
                  LiquidGlassCard(
                    borderRadius: 16,
                    borderColor: _isChainValid == true
                        ? CupertinoColors.activeGreen
                        : CupertinoColors.destructiveRed,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            _isChainValid == true
                                ? CupertinoIcons.checkmark_shield_fill
                                : CupertinoIcons.exclamationmark_shield_fill,
                            color: _isChainValid == true
                                ? CupertinoColors.activeGreen
                                : CupertinoColors.destructiveRed,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isChainValid == true
                                      ? 'Audit Chain Verified'
                                      : 'Integrity Warning',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  _isChainValid == true
                                      ? 'SHA-256 cryptographic chain intact for ${activeCompany.name}.'
                                      : 'Audit records do not match cryptographic checksum chain.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: CupertinoColors.secondaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    elevation: 0,
                    color: _isChainValid == true
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.red.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _isChainValid == true ? Colors.green : Colors.red,
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            _isChainValid == true
                                ? Icons.verified_user_rounded
                                : Icons.gpp_bad_rounded,
                            color: _isChainValid == true ? Colors.green : Colors.red,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isChainValid == true
                                      ? 'Cryptographic Audit Trail Verified'
                                      : 'Audit Integrity Failure Detected',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Append-only SHA-256 chain is immutable and tamper-evident.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Audit Records (${_logs.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (_logs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No audit records found for this company.',
                        style: TextStyle(
                          color: isIos
                              ? CupertinoColors.secondaryLabel
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ..._logs.map((log) {
                    final actionColor = _getActionColor(log.action);
                    final formattedDate =
                        DateFormat('dd MMM yyyy, hh:mm:ss a').format(log.timestamp);

                    if (isIos) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LiquidGlassCard(
                          borderRadius: 14,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: actionColor.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        log.action.displayName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: actionColor,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formattedDate,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: CupertinoColors.secondaryLabel,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Entity: ${log.entityType.toUpperCase()} #${log.entityId}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'User ID: ${log.userId}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: CupertinoColors.secondaryLabel,
                                  ),
                                ),
                                if (log.diffJson != null) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemGrey6,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      log.diffJson!,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'SHA-256: ${log.checksum.substring(0, 16)}...',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: CupertinoColors.tertiaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Chip(
                                  label: Text(
                                    log.action.displayName,
                                    style: TextStyle(
                                      color: actionColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  backgroundColor: actionColor.withValues(alpha: 0.15),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                                Text(
                                  formattedDate,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Entity: ${log.entityType.toUpperCase()} #${log.entityId}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Modified by User: ${log.userId}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (log.diffJson != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  log.diffJson!,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Hash: ${log.checksum.substring(0, 20)}...',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
