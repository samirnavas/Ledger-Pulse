class ActiveBalanceException implements Exception {
  final String message;

  const ActiveBalanceException([this.message = 'Cannot delete a party with an active balance.']);

  @override
  String toString() => message;
}
