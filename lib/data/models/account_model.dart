import 'dart:convert';

enum AccountType {
  asset,
  liability,
  equity,
  income,
  expense;

  String get displayName {
    switch (this) {
      case AccountType.asset:
        return 'Asset';
      case AccountType.liability:
        return 'Liability';
      case AccountType.equity:
        return 'Equity';
      case AccountType.income:
        return 'Income';
      case AccountType.expense:
        return 'Expense';
    }
  }

  /// Normal balance: Assets and Expenses increase with Debit.
  /// Liabilities, Equity, and Income increase with Credit.
  bool get isDebitNormal => this == AccountType.asset || this == AccountType.expense;
}

class AccountModel {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final AccountType type;
  final String? parentAccountId;
  final bool isSystem;
  final bool isActive;
  final String? description;
  final int currentBalanceInCents;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountModel({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.type,
    this.parentAccountId,
    this.isSystem = false,
    this.isActive = true,
    this.description,
    this.currentBalanceInCents = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  AccountModel copyWith({
    String? id,
    String? companyId,
    String? code,
    String? name,
    AccountType? type,
    String? parentAccountId,
    bool? isSystem,
    bool? isActive,
    String? description,
    int? currentBalanceInCents,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AccountModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      parentAccountId: parentAccountId ?? this.parentAccountId,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      description: description ?? this.description,
      currentBalanceInCents: currentBalanceInCents ?? this.currentBalanceInCents,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'code': code,
      'name': name,
      'type': type.name,
      'parentAccountId': parentAccountId,
      'isSystem': isSystem,
      'isActive': isActive,
      'description': description,
      'currentBalanceInCents': currentBalanceInCents,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    return AccountModel(
      id: map['id'] as String,
      companyId: map['companyId'] as String? ?? 'cmp_default',
      code: map['code'] as String,
      name: map['name'] as String,
      type: AccountType.values.firstWhere(
        (e) => e.name.toLowerCase() == (map['type'] as String).toLowerCase(),
        orElse: () => AccountType.asset,
      ),
      parentAccountId: map['parentAccountId'] as String?,
      isSystem: map['isSystem'] as bool? ?? false,
      isActive: map['isActive'] as bool? ?? true,
      description: map['description'] as String?,
      currentBalanceInCents: (map['currentBalanceInCents'] as int?) ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory AccountModel.fromJson(String source) =>
      AccountModel.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// System-defined core chart of accounts constants and factory
class DefaultAccounts {
  // Account IDs
  static const String cashId = 'acc_cash';
  static const String bankId = 'acc_bank';
  static const String arId = 'acc_ar';
  static const String inventoryId = 'acc_inventory';
  static const String inputGstId = 'acc_input_gst';
  static const String inputCgstId = 'acc_input_cgst';
  static const String inputSgstId = 'acc_input_sgst';
  static const String inputIgstId = 'acc_input_igst';

  static const String apId = 'acc_ap';
  static const String outputGstId = 'acc_output_gst';
  static const String outputCgstId = 'acc_output_cgst';
  static const String outputSgstId = 'acc_output_sgst';
  static const String outputIgstId = 'acc_output_igst';

  static const String capitalId = 'acc_capital';
  static const String openingBalanceEquityId = 'acc_opening_balance_equity';
  static const String retainedEarningsId = 'acc_retained_earnings';

  static const String salesId = 'acc_sales';
  static const String otherIncomeId = 'acc_other_income';

  static const String purchasesCogsId = 'acc_purchases_cogs';
  static const String directExpensesId = 'acc_direct_expenses';
  static const String indirectExpensesId = 'acc_indirect_expenses';

  static List<AccountModel> getDefaultAccounts(String companyId, [DateTime? now]) {
    final timestamp = now ?? DateTime.now();
    return [
      // --- ASSETS (1000-1999) ---
      AccountModel(
        id: '${companyId}_$cashId',
        companyId: companyId,
        code: '1000',
        name: 'Cash in Hand',
        type: AccountType.asset,
        isSystem: true,
        description: 'Physical cash on hand',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$bankId',
        companyId: companyId,
        code: '1010',
        name: 'Bank Account',
        type: AccountType.asset,
        isSystem: true,
        description: 'Primary operating bank account',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$arId',
        companyId: companyId,
        code: '1100',
        name: 'Accounts Receivable (Sundry Debtors)',
        type: AccountType.asset,
        isSystem: true,
        description: 'Customer balances owed from credit sales',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$inventoryId',
        companyId: companyId,
        code: '1200',
        name: 'Inventory Asset (Stock-in-Hand)',
        type: AccountType.asset,
        isSystem: true,
        description: 'Total value of merchandise inventory on hand',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$inputGstId',
        companyId: companyId,
        code: '1300',
        name: 'Input GST (Input Tax Credit)',
        type: AccountType.asset,
        isSystem: true,
        description: 'GST paid on purchases eligible for input tax credit',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$inputCgstId',
        companyId: companyId,
        code: '1310',
        name: 'Input CGST',
        type: AccountType.asset,
        parentAccountId: '${companyId}_$inputGstId',
        isSystem: true,
        description: 'Central GST tax credit paid on purchases',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$inputSgstId',
        companyId: companyId,
        code: '1320',
        name: 'Input SGST',
        type: AccountType.asset,
        parentAccountId: '${companyId}_$inputGstId',
        isSystem: true,
        description: 'State GST tax credit paid on purchases',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$inputIgstId',
        companyId: companyId,
        code: '1330',
        name: 'Input IGST',
        type: AccountType.asset,
        parentAccountId: '${companyId}_$inputGstId',
        isSystem: true,
        description: 'Integrated GST tax credit paid on interstate purchases',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),

      // --- LIABILITIES (2000-2999) ---
      AccountModel(
        id: '${companyId}_$apId',
        companyId: companyId,
        code: '2000',
        name: 'Accounts Payable (Sundry Creditors)',
        type: AccountType.liability,
        isSystem: true,
        description: 'Amounts owed to suppliers for credit purchases',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$outputGstId',
        companyId: companyId,
        code: '2100',
        name: 'Output GST (Tax Payable)',
        type: AccountType.liability,
        isSystem: true,
        description: 'GST collected on sales payable to tax authority',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$outputCgstId',
        companyId: companyId,
        code: '2110',
        name: 'Output CGST',
        type: AccountType.liability,
        parentAccountId: '${companyId}_$outputGstId',
        isSystem: true,
        description: 'Central GST collected on sales',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$outputSgstId',
        companyId: companyId,
        code: '2120',
        name: 'Output SGST',
        type: AccountType.liability,
        parentAccountId: '${companyId}_$outputGstId',
        isSystem: true,
        description: 'State GST collected on sales',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$outputIgstId',
        companyId: companyId,
        code: '2130',
        name: 'Output IGST',
        type: AccountType.liability,
        parentAccountId: '${companyId}_$outputGstId',
        isSystem: true,
        description: 'Integrated GST collected on interstate sales',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),

      // --- EQUITY (3000-3999) ---
      AccountModel(
        id: '${companyId}_$capitalId',
        companyId: companyId,
        code: '3000',
        name: "Owner's Capital Account",
        type: AccountType.equity,
        isSystem: true,
        description: 'Owner equity investment and contributed capital',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$openingBalanceEquityId',
        companyId: companyId,
        code: '3100',
        name: 'Opening Balance Equity',
        type: AccountType.equity,
        isSystem: true,
        description: 'Balancing account for historical opening balances',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$retainedEarningsId',
        companyId: companyId,
        code: '3200',
        name: 'Retained Earnings',
        type: AccountType.equity,
        isSystem: true,
        description: 'Accumulated profits and earnings from operations',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),

      // --- INCOME / REVENUE (4000-4999) ---
      AccountModel(
        id: '${companyId}_$salesId',
        companyId: companyId,
        code: '4000',
        name: 'Sales Revenue',
        type: AccountType.income,
        isSystem: true,
        description: 'Gross operating revenue from goods and services sold',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$otherIncomeId',
        companyId: companyId,
        code: '4100',
        name: 'Other Income',
        type: AccountType.income,
        isSystem: true,
        description: 'Non-operating income, discounts received, interest',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),

      // --- EXPENSES (5000-5999) ---
      AccountModel(
        id: '${companyId}_$purchasesCogsId',
        companyId: companyId,
        code: '5000',
        name: 'Purchases / Cost of Goods Sold (COGS)',
        type: AccountType.expense,
        isSystem: true,
        description: 'Direct cost of goods purchased or manufactured for sale',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$directExpensesId',
        companyId: companyId,
        code: '5100',
        name: 'Direct Expenses (Freight, Packaging, Wages)',
        type: AccountType.expense,
        isSystem: true,
        description: 'Direct production and inbound shipping costs',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      AccountModel(
        id: '${companyId}_$indirectExpensesId',
        companyId: companyId,
        code: '5200',
        name: 'Operating & Administrative Expenses',
        type: AccountType.expense,
        isSystem: true,
        description: 'General overhead, rent, electricity, office and admin costs',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ];
  }
}
