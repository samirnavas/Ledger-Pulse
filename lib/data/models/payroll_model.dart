import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class Employee {
  final String id;
  final String companyId;
  final String employeeCode;
  final String fullName;
  final String designation;
  final String department;
  final String? phoneNumber;
  final String? email;
  final String? panNumber;
  final String? uanNumber;
  final String? pfNumber;
  final String? bankAccountNumber;
  final String? bankIfscCode;
  final String? bankName;
  final int basicMonthlySalaryInCents;
  final int hraAllowanceInCents;
  final int specialAllowanceInCents;
  final int conveyanceAllowanceInCents;
  final bool isPfEligible;
  final bool isEsiEligible;
  final bool isProfessionalTaxEligible;
  final int monthlyTdsDeductionInCents;
  final DateTime dateOfJoining;
  final bool isActive;

  const Employee({
    required this.id,
    required this.companyId,
    required this.employeeCode,
    required this.fullName,
    required this.designation,
    required this.department,
    this.phoneNumber,
    this.email,
    this.panNumber,
    this.uanNumber,
    this.pfNumber,
    this.bankAccountNumber,
    this.bankIfscCode,
    this.bankName,
    required this.basicMonthlySalaryInCents,
    this.hraAllowanceInCents = 0,
    this.specialAllowanceInCents = 0,
    this.conveyanceAllowanceInCents = 0,
    this.isPfEligible = true,
    this.isEsiEligible = false,
    this.isProfessionalTaxEligible = true,
    this.monthlyTdsDeductionInCents = 0,
    required this.dateOfJoining,
    this.isActive = true,
  });

  int get grossSalaryInCents =>
      basicMonthlySalaryInCents +
      hraAllowanceInCents +
      specialAllowanceInCents +
      conveyanceAllowanceInCents;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'employeeCode': employeeCode,
      'fullName': fullName,
      'designation': designation,
      'department': department,
      'phoneNumber': phoneNumber,
      'email': email,
      'panNumber': panNumber,
      'uanNumber': uanNumber,
      'pfNumber': pfNumber,
      'bankAccountNumber': bankAccountNumber,
      'bankIfscCode': bankIfscCode,
      'bankName': bankName,
      'basicMonthlySalaryInCents': basicMonthlySalaryInCents,
      'hraAllowanceInCents': hraAllowanceInCents,
      'specialAllowanceInCents': specialAllowanceInCents,
      'conveyanceAllowanceInCents': conveyanceAllowanceInCents,
      'isPfEligible': isPfEligible,
      'isEsiEligible': isEsiEligible,
      'isProfessionalTaxEligible': isProfessionalTaxEligible,
      'monthlyTdsDeductionInCents': monthlyTdsDeductionInCents,
      'dateOfJoining': dateOfJoining.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id'] ?? '',
      companyId: map['companyId'] ?? '',
      employeeCode: map['employeeCode'] ?? '',
      fullName: map['fullName'] ?? '',
      designation: map['designation'] ?? '',
      department: map['department'] ?? '',
      phoneNumber: map['phoneNumber'],
      email: map['email'],
      panNumber: map['panNumber'],
      uanNumber: map['uanNumber'],
      pfNumber: map['pfNumber'],
      bankAccountNumber: map['bankAccountNumber'],
      bankIfscCode: map['bankIfscCode'],
      bankName: map['bankName'],
      basicMonthlySalaryInCents: map['basicMonthlySalaryInCents'] ?? 0,
      hraAllowanceInCents: map['hraAllowanceInCents'] ?? 0,
      specialAllowanceInCents: map['specialAllowanceInCents'] ?? 0,
      conveyanceAllowanceInCents: map['conveyanceAllowanceInCents'] ?? 0,
      isPfEligible: map['isPfEligible'] ?? true,
      isEsiEligible: map['isEsiEligible'] ?? false,
      isProfessionalTaxEligible: map['isProfessionalTaxEligible'] ?? true,
      monthlyTdsDeductionInCents: map['monthlyTdsDeductionInCents'] ?? 0,
      dateOfJoining: DateTime.tryParse(map['dateOfJoining'] ?? '') ?? DateTime.now(),
      isActive: map['isActive'] ?? true,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory Employee.fromJson(String source) => Employee.fromMap(jsonDecode(source));
}

@immutable
class SalarySlip {
  final String id;
  final String companyId;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String designation;
  final String department;
  final String monthYear; // e.g. "September 2026"
  final int workingDays;
  final int presentDays;
  final int basicInCents;
  final int hraInCents;
  final int specialAllowanceInCents;
  final int conveyanceInCents;
  final int grossSalaryInCents;
  final int pfDeductionInCents;
  final int esiDeductionInCents;
  final int profTaxInCents;
  final int tdsInCents;
  final int totalDeductionsInCents;
  final int netPayableInCents;
  final DateTime generatedAt;
  final String? journalVoucherId;

  const SalarySlip({
    required this.id,
    required this.companyId,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.designation,
    required this.department,
    required this.monthYear,
    this.workingDays = 30,
    this.presentDays = 30,
    required this.basicInCents,
    required this.hraInCents,
    required this.specialAllowanceInCents,
    required this.conveyanceInCents,
    required this.grossSalaryInCents,
    required this.pfDeductionInCents,
    required this.esiDeductionInCents,
    required this.profTaxInCents,
    required this.tdsInCents,
    required this.totalDeductionsInCents,
    required this.netPayableInCents,
    required this.generatedAt,
    this.journalVoucherId,
  });
}

@immutable
class PayrollBatchResult {
  final String monthYear;
  final int totalEmployeesProcessed;
  final int totalGrossInCents;
  final int totalPfInCents;
  final int totalEsiInCents;
  final int totalProfTaxInCents;
  final int totalTdsInCents;
  final int totalNetPayoutInCents;
  final List<SalarySlip> slips;
  final String? journalVoucherId;

  const PayrollBatchResult({
    required this.monthYear,
    required this.totalEmployeesProcessed,
    required this.totalGrossInCents,
    required this.totalPfInCents,
    required this.totalEsiInCents,
    required this.totalProfTaxInCents,
    required this.totalTdsInCents,
    required this.totalNetPayoutInCents,
    required this.slips,
    this.journalVoucherId,
  });
}
