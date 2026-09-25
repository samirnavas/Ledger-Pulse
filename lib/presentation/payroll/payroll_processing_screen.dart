import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/payroll_model.dart';
import '../../data/services/payroll_service.dart';
import '../providers/company_providers.dart';
import '../providers/voucher_providers.dart';
import 'employee_list_screen.dart';

class PayrollProcessingScreen extends ConsumerStatefulWidget {
  const PayrollProcessingScreen({super.key});

  @override
  ConsumerState<PayrollProcessingScreen> createState() =>
      _PayrollProcessingScreenState();
}

class _PayrollProcessingScreenState
    extends ConsumerState<PayrollProcessingScreen> {
  String _selectedMonth = 'September 2026';
  PayrollBatchResult? _batchResult;
  bool _isPosting = false;
  String? _postedVoucherNumber;

  @override
  void initState() {
    super.initState();
    _recalculateBatch();
  }

  void _recalculateBatch() {
    final company = ref.read(activeCompanyProvider);
    final employees = ref.read(employeeListProvider);
    final result = PayrollService.processBulkPayroll(
      company: company,
      employees: employees,
      monthYear: _selectedMonth,
    );
    setState(() {
      _batchResult = result;
      _postedVoucherNumber = null;
    });
  }

  Future<void> _postPayrollJournal() async {
    if (_batchResult == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _isPosting = true);

    try {
      final company = ref.read(activeCompanyProvider);
      final voucher = PayrollService.createPayrollJournalVoucher(
        company: company,
        batchResult: _batchResult!,
      );

      final postingEngine = ref.read(voucherPostingEngineProvider);
      final posted = await postingEngine.postVoucher(
        voucher: voucher,
        userId: 'USR-ADMIN',
      );

      if (mounted) {
        setState(() {
          _postedVoucherNumber = posted.voucherNumber;
          _isPosting = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payroll Journal Posted: ${posted.voucherNumber}'),
            backgroundColor: AppColors.receivableGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post payroll journal: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
  }

  Future<void> _viewAndPrintSlip(SalarySlip slip) async {
    HapticFeedback.lightImpact();
    final company = ref.read(activeCompanyProvider);
    final employees = ref.read(employeeListProvider);
    final emp = employees.firstWhere(
      (e) => e.id == slip.employeeId,
      orElse: () => Employee(
        id: slip.employeeId,
        companyId: slip.companyId,
        employeeCode: slip.employeeCode,
        fullName: slip.employeeName,
        designation: slip.designation,
        department: slip.department,
        basicMonthlySalaryInCents: slip.basicInCents,
        dateOfJoining: DateTime.now(),
      ),
    );

    final pdfBytes = await PayrollService.generateSalarySlipPdf(
      slip: slip,
      company: company,
      employee: emp,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
      name: 'SalarySlip_${slip.employeeCode}_${slip.monthYear.replaceAll(" ", "_")}.pdf',
    );
  }

  Future<void> _shareSlip(SalarySlip slip) async {
    HapticFeedback.lightImpact();
    final company = ref.read(activeCompanyProvider);
    final employees = ref.read(employeeListProvider);
    final emp = employees.firstWhere((e) => e.id == slip.employeeId);

    final pdfBytes = await PayrollService.generateSalarySlipPdf(
      slip: slip,
      company: company,
      employee: emp,
    );

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/SalarySlip_${slip.employeeCode}.pdf');
    await file.writeAsBytes(pdfBytes);

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      text: 'Salary Slip for ${slip.employeeName} (${slip.monthYear})',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = _batchResult;

    return AdaptiveScaffold(
      title: 'Bulk Payroll Processing',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month Selector Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Payroll Period:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                DropdownButton<String>(
                  value: _selectedMonth,
                  items: const [
                    DropdownMenuItem(value: 'September 2026', child: Text('September 2026')),
                    DropdownMenuItem(value: 'August 2026', child: Text('August 2026')),
                    DropdownMenuItem(value: 'July 2026', child: Text('July 2026')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedMonth = val);
                      _recalculateBatch();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Summary Statistics Metric Cards
            if (result != null) ...[
              _buildMetricSummary(isIos, isDark, result),
              const SizedBox(height: 16),

              // Post Journal & Batch Controls
              Row(
                children: [
                  Expanded(
                    child: AdaptiveButton(
                      type: _postedVoucherNumber != null ? AdaptiveButtonType.secondary : AdaptiveButtonType.primary,
                      onPressed: _isPosting || _postedVoucherNumber != null ? () {} : _postPayrollJournal,
                      child: _isPosting
                          ? const CupertinoActivityIndicator()
                          : Text(
                              _postedVoucherNumber != null
                                  ? 'Posted: $_postedVoucherNumber'
                                  : 'Post Payroll Journal & Ledger',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Employee Payslips Table
              const Text('Generated Employee Salary Slips', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),

              ...result.slips.map((slip) {
                final tile = Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.15),
                        child: Text(
                          slip.employeeName.substring(0, 1),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(slip.employeeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(
                              '${slip.designation} • Gross: ₹${(slip.grossSalaryInCents / 100.0).toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹ ${(slip.netPayableInCents / 100.0).toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.receivableGreen),
                          ),
                          const Text('Net Pay', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Print / Preview Slip',
                        icon: Icon(
                          isIos ? CupertinoIcons.printer : Icons.print_rounded,
                          size: 20,
                        ),
                        onPressed: () => _viewAndPrintSlip(slip),
                      ),
                      IconButton(
                        tooltip: 'Share Slip PDF',
                        icon: Icon(
                          isIos ? CupertinoIcons.share : Icons.share_rounded,
                          size: 20,
                        ),
                        onPressed: () => _shareSlip(slip),
                      ),
                    ],
                  ),
                );

                if (isIos) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LiquidGlassCard(borderRadius: 18, padding: EdgeInsets.zero, child: tile),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5)),
                    ),
                    child: tile,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricSummary(bool isIos, bool isDark, PayrollBatchResult result) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('Total Gross Payroll', '₹ ${(result.totalGrossInCents / 100.0).toStringAsFixed(2)}'),
              _buildStat('Net Disbursal', '₹ ${(result.totalNetPayoutInCents / 100.0).toStringAsFixed(2)}', isHighlight: true),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat('PF Deduction', '₹ ${(result.totalPfInCents / 100.0).toStringAsFixed(2)}'),
              _buildMiniStat('ESI Deduction', '₹ ${(result.totalEsiInCents / 100.0).toStringAsFixed(2)}'),
              _buildMiniStat('Prof Tax (PT)', '₹ ${(result.totalProfTaxInCents / 100.0).toStringAsFixed(2)}'),
              _buildMiniStat('TDS', '₹ ${(result.totalTdsInCents / 100.0).toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(borderRadius: 22, padding: EdgeInsets.zero, child: content);
    }
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5)),
      ),
      child: content,
    );
  }

  Widget _buildStat(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: isHighlight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppColors.receivableGreen : null,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
