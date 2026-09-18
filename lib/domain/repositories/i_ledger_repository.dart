import '../../data/models/party_model.dart';
import '../../data/models/transaction_model.dart';

abstract class ILedgerRepository {
  Future<List<Party>> getParties({PartyType? filter});
  Future<Party> getPartyById(String partyId);
  Future<void> addParty(Party party);
  Future<List<LedgerEntry>> getEntriesForParty(String partyId);
  Future<void> addEntry(LedgerEntry entry);
  Future<void> deleteEntry(String entryId);
  Future<(int totalReceivable, int totalPayable)> getBusinessSummary();
  Stream<void> get repositoryUpdatesStream;
}
