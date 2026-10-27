import '../../data/models/company_mode.dart';
import '../../data/models/subscription_tier_model.dart';

class ActiveBalanceException implements Exception {

  final String message;

  const ActiveBalanceException([this.message = 'Cannot delete a party with an active balance.']);

  @override
  String toString() => message;
}

class UnbalancedJournalException implements Exception {
  final int totalDebit;
  final int totalCredit;
  final String message;

  UnbalancedJournalException({
    required this.totalDebit,
    required this.totalCredit,
    String? message,
  }) : message = message ??
            'Total Debit ($totalDebit cents) does not equal Total Credit ($totalCredit cents). Transaction rejected.';

  @override
  String toString() => message;
}

class AccountNotFoundException implements Exception {
  final String accountId;
  final String message;

  AccountNotFoundException(this.accountId, [String? message])
      : message = message ?? 'Account not found: $accountId';

  @override
  String toString() => message;
}

/// Thrown when an operation is attempted on an application module that is disabled
/// or not entitled for the active company.
class ModuleDisabledException implements Exception {
  final AppModule module;
  final String message;

  ModuleDisabledException(this.module, [String? message])
      : message = message ??
            'Module ${module.name} is disabled or not entitled for the active company.';

  @override
  String toString() => message;
}

/// Thrown when company creation exceeds the active subscription tier limit.
class CompanyLimitExceededException implements Exception {
  final SubscriptionTier tier;
  final int maxCompanies;
  final String message;

  CompanyLimitExceededException(this.tier, [String? message])
      : maxCompanies = tier.maxCompanies,
        message = message ??
            'Company limit of ${tier.maxCompanies} reached for ${tier.displayName}. Upgrade to create more companies.';

  @override
  String toString() => message;
}

/// Thrown when a voucher fails business logic validation rules
/// (e.g., zero/negative amount, mismatched company on wallet/category, invalid category type, etc.).
class VoucherValidationException implements Exception {
  final String message;

  const VoucherValidationException(this.message);

  @override
  String toString() => message;
}

/// Thrown when an expense repository operation is attempted on a company not in expenseTracker mode.
class ExpenseModeRequiredException implements Exception {
  final String message;

  const ExpenseModeRequiredException([
    this.message = 'Expense repository operations are only supported when company mode is expenseTracker.',
  ]);

  @override
  String toString() => message;
}


