import '../models/transaction_model.dart';
import 'database.dart';

/// Voids are audit records. Older releases also wrote an opposite entry with
/// a generated note. Match the original before treating that row as an offset.
final class LedgerEntryBalance {
  LedgerEntryBalance(Iterable<LedgerEntryTableData> rows)
    : _byId = {for (final row in rows) row.id: row};

  final Map<String, LedgerEntryTableData> _byId;
  static final _offsetNote = RegExp(
    r'^(?:Reversal: Voided entry #([^ ]+)|Offset: Voided entry #([^ ]+)(?: \([\s\S]*\))?)$',
  );

  bool isLegacyOffset(LedgerEntryTableData row) {
    final match = _offsetNote.firstMatch(row.note ?? '');
    if (match == null) return false;
    final original = _byId[match[1] ?? match[2]];
    return original != null &&
        original.companyId == row.companyId &&
        original.partyId == row.partyId &&
        (original.isVoided || original.isDeleted) &&
        original.type != row.type &&
        original.amountInCents == row.amountInCents;
  }

  int delta(LedgerEntryTableData row) {
    if (row.isDeleted || row.isVoided || isLegacyOffset(row)) return 0;
    return row.type == EntryType.gave ? row.amountInCents : -row.amountInCents;
  }
}

int calculatePartyBalanceFromRows(List<LedgerEntryTableData> rows) {
  final balance = LedgerEntryBalance(rows);
  return rows.fold(0, (total, row) => total + balance.delta(row));
}

Future<Map<String, int>> readLedgerPartyBalances(
  AppDatabase db,
  String companyId,
) async {
  final rows = await (db.select(
    db.ledgerEntries,
  )..where((row) => row.companyId.equals(companyId))).get();
  final balance = LedgerEntryBalance(rows);
  final totals = <String, int>{};
  for (final row in rows) {
    totals[row.partyId] = (totals[row.partyId] ?? 0) + balance.delta(row);
  }
  return totals;
}
