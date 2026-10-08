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
