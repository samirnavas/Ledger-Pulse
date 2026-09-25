import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/payroll_model.dart';
import '../providers/company_providers.dart';
import 'payroll_processing_screen.dart';

class EmployeeListNotifier extends Notifier<List<Employee>> {
  @override
  List<Employee> build() {
    final company = ref.watch(activeCompanyProvider);
    return [
    Employee(
      id: 'emp_1',
      companyId: company.id,
      employeeCode: 'EMP-001',
      fullName: 'Rahul Sharma',
      designation: 'Senior Accountant',
      department: 'Finance',
      phoneNumber: '+91 98765 43210',
      email: 'rahul.sharma@example.com',
      panNumber: 'ABCPS1234F',
      uanNumber: '100904561234',
      pfNumber: 'MH/BAN/0012345/000/0001',
      bankAccountNumber: '91823456789012',
      bankIfscCode: 'HDFC0001234',
      bankName: 'HDFC Bank',
      basicMonthlySalaryInCents: 4500000, // ₹45,000
      hraAllowanceInCents: 1800000,       // ₹18,000
      specialAllowanceInCents: 700000,    // ₹7,000
      conveyanceAllowanceInCents: 200000, // ₹2,000
      isPfEligible: true,
      isEsiEligible: false,
      isProfessionalTaxEligible: true,
      monthlyTdsDeductionInCents: 250000, // ₹2,500
      dateOfJoining: DateTime(2023, 4, 1),
    ),
    Employee(
      id: 'emp_2',
      companyId: company.id,
      employeeCode: 'EMP-002',
      fullName: 'Pooja Nair',
      designation: 'Inventory Manager',
      department: 'Operations',
      phoneNumber: '+91 98220 11223',
      email: 'pooja.nair@example.com',
      panNumber: 'BJKPN4321K',
      uanNumber: '100904565678',
      bankAccountNumber: '50100234567891',
      bankIfscCode: 'ICIC0000456',
      bankName: 'ICICI Bank',
      basicMonthlySalaryInCents: 3500000, // ₹35,000
      hraAllowanceInCents: 1400000,       // ₹14,000
      specialAllowanceInCents: 500000,    // ₹5,000
      isPfEligible: true,
      isEsiEligible: false,
      isProfessionalTaxEligible: true,
      monthlyTdsDeductionInCents: 120000,
      dateOfJoining: DateTime(2024, 1, 15),
    ),
    Employee(
      id: 'emp_3',
      companyId: company.id,
      employeeCode: 'EMP-003',
      fullName: 'Amit Kumar',
      designation: 'Logistics Supervisor',
      department: 'Logistics',
      phoneNumber: '+91 97110 99887',
      panNumber: 'CYPPA9876D',
      bankAccountNumber: '302001928374',
      bankIfscCode: 'SBIN0001122',
      bankName: 'State Bank of India',
      basicMonthlySalaryInCents: 2000000, // ₹20,000
      hraAllowanceInCents: 800000,        // ₹8,000
      specialAllowanceInCents: 200000,    // ₹2,000
      isPfEligible: true,
      isEsiEligible: true,
      isProfessionalTaxEligible: true,
      monthlyTdsDeductionInCents: 0,
      dateOfJoining: DateTime(2024, 8, 1),
    ),
  ];
  }

  void addEmployee(Employee emp) {
    state = [...state, emp];
  }
}

final employeeListProvider =
    NotifierProvider<EmployeeListNotifier, List<Employee>>(
  EmployeeListNotifier.new,
);

class EmployeeListScreen extends ConsumerStatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  ConsumerState<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends ConsumerState<EmployeeListScreen> {
  String _searchQuery = '';

  void _showAddEmployeeModal() {
    final company = ref.read(activeCompanyProvider);
    final codeCtrl = TextEditingController(text: 'EMP-00${ref.read(employeeListProvider).length + 1}');
    final nameCtrl = TextEditingController();
    final desigCtrl = TextEditingController();
    final deptCtrl = TextEditingController(text: 'General');
    final salaryCtrl = TextEditingController(text: '30000');
    final panCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add New Employee', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(AdaptiveThemeHelper.isIos(ctx) ? CupertinoIcons.xmark : Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'Employee Code', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: desigCtrl,
                      decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: deptCtrl,
                      decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: salaryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Basic Monthly Salary (₹)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: panCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'PAN Number', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: ifscCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Bank IFSC Code', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AdaptiveButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final basicSalary = int.tryParse(salaryCtrl.text.trim()) ?? 30000;
                    final newEmp = Employee(
                      id: 'emp_${DateTime.now().millisecondsSinceEpoch}',
                      companyId: company.id,
                      employeeCode: codeCtrl.text.trim(),
                      fullName: nameCtrl.text.trim(),
                      designation: desigCtrl.text.trim().isEmpty ? 'Associate' : desigCtrl.text.trim(),
                      department: deptCtrl.text.trim().isEmpty ? 'General' : deptCtrl.text.trim(),
                      basicMonthlySalaryInCents: basicSalary * 100,
                      hraAllowanceInCents: (basicSalary * 0.4 * 100).round(),
                      specialAllowanceInCents: (basicSalary * 0.15 * 100).round(),
                      panNumber: panCtrl.text.trim().isNotEmpty ? panCtrl.text.trim() : null,
                      bankIfscCode: ifscCtrl.text.trim().isNotEmpty ? ifscCtrl.text.trim() : null,
                      dateOfJoining: DateTime.now(),
                    );
                    ref.read(employeeListProvider.notifier).addEmployee(newEmp);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save Employee'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final employees = ref.watch(employeeListProvider);

    final filtered = employees.where((emp) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return emp.fullName.toLowerCase().contains(q) ||
          emp.employeeCode.toLowerCase().contains(q) ||
          emp.designation.toLowerCase().contains(q) ||
          emp.department.toLowerCase().contains(q);
    }).toList();

    return AdaptiveScaffold(
      title: 'Payroll & Employees',
      actions: [
        IconButton(
          tooltip: 'Process Monthly Payroll',
          icon: Icon(isIos ? CupertinoIcons.money_dollar_circle : Icons.payments_rounded),
          onPressed: () {
            Navigator.of(context).push(
              createAdaptivePageRoute(builder: (_) => const PayrollProcessingScreen()),
            );
          },
        ),
      ],
      body: Column(
        children: [
          // Search & Action Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search by employee, code, or department...',
                      prefixIcon: Icon(
                        isIos ? CupertinoIcons.search : Icons.search_rounded,
                        size: 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isIos
                          ? (isDark
                              ? CupertinoColors.systemGrey6.darkColor
                              : CupertinoColors.systemGrey6)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _showAddEmployeeModal,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                  ),
                  icon: Icon(
                    isIos ? CupertinoIcons.person_add : Icons.person_add_rounded,
                    size: 18,
                  ),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),

          // Employee List with swipe-down-to-refresh
          Expanded(
            child: RefreshIndicator.adaptive(
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref.invalidate(employeeListProvider);
              },
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: EmptyStateView(
                            title: 'No Employees Found',
                            subtitle: 'Add employee records to start managing payroll and generating salary slips.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                      final emp = filtered[index];
                      final tile = Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Text(
                                emp.fullName.isNotEmpty ? emp.fullName.substring(0, 1).toUpperCase() : 'E',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        emp.fullName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          emp.employeeCode,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${emp.designation} • ${emp.department}',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                  ),
                                  if (emp.panNumber != null) ...[
                                    const SizedBox(height: 2),
                                    Text('PAN: ${emp.panNumber}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹ ${(emp.grossSalaryInCents / 100.0).toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                const Text('Gross/mo', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                      );

                      if (isIos) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: LiquidGlassCard(borderRadius: 20, padding: EdgeInsets.zero, child: tile),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
