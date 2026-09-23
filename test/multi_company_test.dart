import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DriftLedgerRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftLedgerRepository(
      db: db,
      currentCompanyId: 'cmp_1',
      currentUserId: 'usr_admin',
      currentRole: Role.admin,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Multi-Company Isolation (FR-CMP-01, FR-CMP-02) Tests', () {
    test('Parties and Ledger Entries are partitioned strictly by companyId', () async {
      // 1. In Company 1, create a customer party and transaction
      final partyCmp1 = Party(
        id: 'party_cmp1_001',
        name: 'Alpha Customer',
        phoneNumber: '+91 99999 11111',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now(),
      );
      await repo.addParty(partyCmp1);

      final entryCmp1 = LedgerEntry(
        id: 'entry_cmp1_001',
        partyId: partyCmp1.id,
        amountInCents: 15000,
        type: EntryType.gave,
        date: DateTime.now(),
        note: 'Invoice 101',
      );
      await repo.addEntry(entryCmp1);

      final cmp1Parties = await repo.getParties();
      expect(cmp1Parties.length, equals(1));
      expect(cmp1Parties.first.id, equals('party_cmp1_001'));

      final (cmp1Rec, cmp1Pay) = await repo.getBusinessSummary();
      expect(cmp1Rec, equals(15000));
      expect(cmp1Pay, equals(0));

      // 2. Switch context to Company 2
      repo.setContext(companyId: 'cmp_2');

      // In Company 2, there should be 0 parties and 0 balance
      final cmp2PartiesInitial = await repo.getParties();
      expect(cmp2PartiesInitial.isEmpty, isTrue);

      final (cmp2RecInitial, cmp2PayInitial) = await repo.getBusinessSummary();
      expect(cmp2RecInitial, equals(0));
      expect(cmp2PayInitial, equals(0));

      // 3. In Company 2, create a supplier party and transaction
      final partyCmp2 = Party(
        id: 'party_cmp2_001',
        name: 'Beta Supplier',
        phoneNumber: '+91 88888 22222',
        type: PartyType.supplier,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now(),
      );
      await repo.addParty(partyCmp2);

      final entryCmp2 = LedgerEntry(
        id: 'entry_cmp2_001',
        partyId: partyCmp2.id,
        amountInCents: 8000,
        type: EntryType.got,
        date: DateTime.now(),
        note: 'Purchase bill',
      );
      await repo.addEntry(entryCmp2);

      final cmp2Parties = await repo.getParties();
      expect(cmp2Parties.length, equals(1));
      expect(cmp2Parties.first.id, equals('party_cmp2_001'));

      final (cmp2Rec, cmp2Pay) = await repo.getBusinessSummary();
      expect(cmp2Rec, equals(0));
      expect(cmp2Pay, equals(8000));

      // 4. Switch back to Company 1 and verify data remains untouched
      repo.setContext(companyId: 'cmp_1');
      final cmp1PartiesCheck = await repo.getParties();
      expect(cmp1PartiesCheck.length, equals(1));
      expect(cmp1PartiesCheck.first.id, equals('party_cmp1_001'));

      final (cmp1RecCheck, _) = await repo.getBusinessSummary();
      expect(cmp1RecCheck, equals(15000));
    });

    test('Creating new company persists and can be queried', () async {
      final newCompany = Company(
        id: 'cmp_branch_hyd',
        name: 'Hyderabad Branch Ltd',
        legalName: 'Hyderabad Branch Enterprises Pvt Ltd',
        gstin: '36ABCDE1234F1Z5',
        currencyCode: 'INR',
        address: 'Hitech City, Hyderabad',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final created = await repo.createCompany(newCompany);
      expect(created.id, equals('cmp_branch_hyd'));

      final companies = await repo.getCompanies();
      expect(companies.any((c) => c.id == 'cmp_branch_hyd'), isTrue);
    });
  });
}
