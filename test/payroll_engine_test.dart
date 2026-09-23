import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/payroll_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/payroll_service.dart';

void main() {
  group('Payroll Module & Statutory Deduction Tests (FR-PAY-01, FR-PAY-02, FR-PAY-03)', () {
    late Company testCompany;
    late Employee emp1;
    late Employee emp2;

    setUp(() {
      testCompany = Company(
        id: 'cmp_test_1',
        name: 'TechMatrix Global Pvt Ltd',
        legalName: 'TechMatrix Global Pvt Ltd',
        gstin: '27AABCU9603R1ZM',
        stateCode: '27',
        address: 'BKC, Mumbai, Maharashtra 400051',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      emp1 = Employee(
        id: 'emp_101',
        companyId: testCompany.id,
        employeeCode: 'EMP-101',
        fullName: 'Vikram Mehta',
        designation: 'Staff Accountant',
        department: 'Finance',
        basicMonthlySalaryInCents: 5000000, // ₹50,000
        hraAllowanceInCents: 2000000,       // ₹20,000
        specialAllowanceInCents: 1000000,    // ₹10,000
        isPfEligible: true,
        isEsiEligible: false,
        isProfessionalTaxEligible: true,
        monthlyTdsDeductionInCents: 300000, // ₹3,000
        dateOfJoining: DateTime(2023, 1, 1),
      );

      emp2 = Employee(
        id: 'emp_102',
        companyId: testCompany.id,
        employeeCode: 'EMP-102',
        fullName: 'Ananya Sen',
        designation: 'Junior Associate',
        department: 'Support',
        basicMonthlySalaryInCents: 1500000, // ₹15,000
        hraAllowanceInCents: 400000,        // ₹4,000
        isPfEligible: true,
        isEsiEligible: true, // Gross <= 21,000 -> ESI @ 0.75%
        isProfessionalTaxEligible: true,
        monthlyTdsDeductionInCents: 0,
        dateOfJoining: DateTime(2024, 2, 1),
      );
    });

    test('computeSalarySlip accurately calculates gross, PF, PT, TDS, and net payable', () {
      final slip = PayrollService.computeSalarySlip(
        employee: emp1,
        monthYear: 'September 2026',
      );

      expect(slip.grossSalaryInCents, equals(8000000)); // ₹80,000 gross
      expect(slip.basicInCents, equals(5000000));       // ₹50,000
      expect(slip.pfDeductionInCents, equals(600000));   // 12% of Basic = ₹6,000
      expect(slip.esiDeductionInCents, equals(0));       // Ineligible (Gross > 21k)
      expect(slip.profTaxInCents, equals(20000));        // ₹200 Standard PT
      expect(slip.tdsInCents, equals(300000));          // ₹3,000 TDS
      expect(slip.totalDeductionsInCents, equals(920000)); // ₹9,200 total
      expect(slip.netPayableInCents, equals(7080000));   // ₹70,800 net
    });

    test('computeSalarySlip accurately applies ESI @ 0.75% for eligible employee', () {
      final slip = PayrollService.computeSalarySlip(
        employee: emp2,
        monthYear: 'September 2026',
      );

      expect(slip.grossSalaryInCents, equals(1900000)); // ₹19,000 gross
      expect(slip.pfDeductionInCents, equals(180000));   // 12% of 15k = ₹1,800
      expect(slip.esiDeductionInCents, equals(14250));   // 0.75% of 19k = ₹142.50
      expect(slip.profTaxInCents, equals(20000));        // ₹200
      expect(slip.netPayableInCents, equals(1685750));   // ₹16,857.50
    });

    test('processBulkPayroll aggregates multi-employee batch and creates double-entry journal', () {
      final batch = PayrollService.processBulkPayroll(
        company: testCompany,
        employees: [emp1, emp2],
        monthYear: 'September 2026',
      );

      expect(batch.totalEmployeesProcessed, equals(2));
      expect(batch.totalGrossInCents, equals(9900000)); // 80k + 19k = 99k
      expect(batch.totalPfInCents, equals(780000));     // 6k + 1.8k = 7.8k
      expect(batch.totalNetPayoutInCents, equals(8765750)); // 70.8k + 16.8575k

      final journal = PayrollService.createPayrollJournalVoucher(
        company: testCompany,
        batchResult: batch,
      );

      expect(journal.type, equals(VoucherType.journal));
      expect(journal.totalAmountInCents, equals(9900000));
      expect(journal.narration, contains('Payroll liability posted for September 2026'));
    });

    test('generateSalarySlipPdf generates valid binary PDF bytes', () async {
      final slip = PayrollService.computeSalarySlip(
        employee: emp1,
        monthYear: 'September 2026',
      );

      final pdfBytes = await PayrollService.generateSalarySlipPdf(
        slip: slip,
        company: testCompany,
        employee: emp1,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46])); // %PDF header
    });
  });
}
