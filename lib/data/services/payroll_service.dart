import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company_model.dart';
import '../models/payroll_model.dart';
import '../models/voucher_model.dart';

class PayrollService {
  /// Computes individual salary slip for an employee for a given month
  static SalarySlip computeSalarySlip({
    required Employee employee,
    required String monthYear,
    int workingDays = 30,
    int presentDays = 30,
  }) {
    final ratio = workingDays > 0 ? presentDays / workingDays : 1.0;

    final basic = (employee.basicMonthlySalaryInCents * ratio).round();
    final hra = (employee.hraAllowanceInCents * ratio).round();
    final special = (employee.specialAllowanceInCents * ratio).round();
    final conveyance = (employee.conveyanceAllowanceInCents * ratio).round();
    final gross = basic + hra + special + conveyance;

    // 1. PF: 12% of Basic (if eligible)
    int pf = 0;
    if (employee.isPfEligible) {
      pf = (basic * 0.12).round();
    }

    // 2. ESI: 0.75% of Gross if gross <= ₹21,000 (2,100,000 cents) and eligible
    int esi = 0;
    if (employee.isEsiEligible && gross <= 2100000) {
      esi = (gross * 0.0075).round();
    }

    // 3. Professional Tax (PT): Standard ₹200/month (20,000 cents) if gross > ₹15,000
    int pt = 0;
    if (employee.isProfessionalTaxEligible && gross > 1500000) {
      pt = 20000;
    }

    // 4. TDS
    final tds = employee.monthlyTdsDeductionInCents;

    final totalDeductions = pf + esi + pt + tds;
    final netPayable = gross - totalDeductions;

    return SalarySlip(
      id: 'slip_${employee.id}_${DateTime.now().millisecondsSinceEpoch}',
      companyId: employee.companyId,
      employeeId: employee.id,
      employeeName: employee.fullName,
      employeeCode: employee.employeeCode,
      designation: employee.designation,
      department: employee.department,
      monthYear: monthYear,
      workingDays: workingDays,
      presentDays: presentDays,
      basicInCents: basic,
      hraInCents: hra,
      specialAllowanceInCents: special,
      conveyanceInCents: conveyance,
      grossSalaryInCents: gross,
      pfDeductionInCents: pf,
      esiDeductionInCents: esi,
      profTaxInCents: pt,
      tdsInCents: tds,
      totalDeductionsInCents: totalDeductions,
      netPayableInCents: netPayable > 0 ? netPayable : 0,
      generatedAt: DateTime.now(),
    );
  }

  /// Processes bulk payroll for all active employees of a company
  static PayrollBatchResult processBulkPayroll({
    required Company company,
    required List<Employee> employees,
    required String monthYear,
  }) {
    final activeEmployees = employees.where((e) => e.isActive).toList();
    final slips = <SalarySlip>[];

    int totalGross = 0;
    int totalPf = 0;
    int totalEsi = 0;
    int totalPt = 0;
    int totalTds = 0;
    int totalNet = 0;

    for (final emp in activeEmployees) {
      final slip = computeSalarySlip(employee: emp, monthYear: monthYear);
      slips.add(slip);

      totalGross += slip.grossSalaryInCents;
      totalPf += slip.pfDeductionInCents;
      totalEsi += slip.esiDeductionInCents;
      totalPt += slip.profTaxInCents;
      totalTds += slip.tdsInCents;
      totalNet += slip.netPayableInCents;
    }

    return PayrollBatchResult(
      monthYear: monthYear,
      totalEmployeesProcessed: activeEmployees.length,
      totalGrossInCents: totalGross,
      totalPfInCents: totalPf,
      totalEsiInCents: totalEsi,
      totalProfTaxInCents: totalPt,
      totalTdsInCents: totalTds,
      totalNetPayoutInCents: totalNet,
      slips: slips,
    );
  }

  /// Creates a double-entry Journal Voucher for posting the monthly payroll liability
  static VoucherModel createPayrollJournalVoucher({
    required Company company,
    required PayrollBatchResult batchResult,
  }) {
    final now = DateTime.now();
    final voucherNumber = 'PAYROLL-${DateFormat('yyyyMM').format(now)}-${now.millisecondsSinceEpoch.toString().substring(8)}';

    return VoucherModel(
      id: 'vch_payroll_${now.millisecondsSinceEpoch}',
      companyId: company.id,
      voucherNumber: voucherNumber,
      type: VoucherType.journal,
      date: now,
      status: VoucherStatus.posted,
      subtotalInCents: batchResult.totalGrossInCents,
      taxInCents: 0,
      discountInCents: 0,
      totalAmountInCents: batchResult.totalGrossInCents,
      narration: 'Payroll liability posted for ${batchResult.monthYear} covering ${batchResult.totalEmployeesProcessed} employees. Net Payable: ₹${(batchResult.totalNetPayoutInCents / 100.0).toStringAsFixed(2)}, PF: ₹${(batchResult.totalPfInCents / 100.0).toStringAsFixed(2)}, ESI: ₹${(batchResult.totalEsiInCents / 100.0).toStringAsFixed(2)}, PT: ₹${(batchResult.totalProfTaxInCents / 100.0).toStringAsFixed(2)}, TDS: ₹${(batchResult.totalTdsInCents / 100.0).toStringAsFixed(2)}',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Generates printable computer-generated PDF Salary Slip
  static Future<Uint8List> generateSalarySlipPdf({
    required SalarySlip slip,
    required Company company,
    required Employee employee,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        company.name.toUpperCase(),
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                      ),
                      if (company.gstin != null)
                        pw.Text('GSTIN: ${company.gstin}', style: const pw.TextStyle(fontSize: 10)),
                      if (company.address != null)
                        pw.Text(company.address!, style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'SALARY SLIP',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                      ),
                      pw.Text(slip.monthYear, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(thickness: 1.5),
              pw.SizedBox(height: 10),

              // Employee Info Box
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow('Employee Name:', slip.employeeName),
                          _buildInfoRow('Employee Code:', slip.employeeCode),
                          _buildInfoRow('Designation:', slip.designation),
                          _buildInfoRow('Department:', slip.department),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow('Bank A/C:', employee.bankAccountNumber ?? 'N/A'),
                          _buildInfoRow('Bank IFSC:', employee.bankIfscCode ?? 'N/A'),
                          _buildInfoRow('PAN Number:', employee.panNumber ?? 'N/A'),
                          _buildInfoRow('UAN / PF:', employee.uanNumber ?? employee.pfNumber ?? 'N/A'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Earnings & Deductions Breakdown
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Earnings Table
                  pw.Expanded(
                    child: pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Earnings', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text('Amount (₹)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        _buildTableRow('Basic Salary', slip.basicInCents),
                        _buildTableRow('HRA Allowance', slip.hraInCents),
                        _buildTableRow('Special Allowance', slip.specialAllowanceInCents),
                        _buildTableRow('Conveyance', slip.conveyanceInCents),
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Gross Earnings', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text(
                                  (slip.grossSalaryInCents / 100.0).toStringAsFixed(2),
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 14),

                  // Deductions Table
                  pw.Expanded(
                    child: pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Deductions', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text('Amount (₹)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        _buildTableRow('Provident Fund (PF)', slip.pfDeductionInCents),
                        _buildTableRow('ESI Deduction', slip.esiDeductionInCents),
                        _buildTableRow('Professional Tax', slip.profTaxInCents),
                        _buildTableRow('TDS / Income Tax', slip.tdsInCents),
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('Total Deductions', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text(
                                  (slip.totalDeductionsInCents / 100.0).toStringAsFixed(2),
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Net Pay Highlight Box
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.blue300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'NET TAKE-HOME SALARY:',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                    ),
                    pw.Text(
                      '₹ ${(slip.netPayableInCents / 100.0).toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // Signatures & Computer generated note
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'This is a computer-generated document and requires no physical signature.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'For ${company.name}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 24),
                      pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static pw.TableRow _buildTableRow(String label, int cents) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text((cents / 100.0).toStringAsFixed(2), style: const pw.TextStyle(fontSize: 9)),
          ),
        ),
      ],
    );
  }
}
