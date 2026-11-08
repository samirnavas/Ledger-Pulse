import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/data/mock/mock_auth_repository.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testAccountId = 'a0000000-0000-4000-8000-000000000001';

  group('Profile Type Canonical Serialization and Parsing Tests', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late DriftProfileRepository profileRepo;
    late DriftLedgerRepository ledgerRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db, simulateSyncForTesting: true);
      profileRepo = DriftProfileRepository(db: db, syncEngine: syncEngine);
      final audit = AuditService(db);
      final posting = VoucherPostingEngine(db, audit);
      ledgerRepo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        postingEngine: posting,
        autoSync: false,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('1. An Expense profile remains Expense after local database reload', () async {
      // 1. Create an Expense profile
      final created = await profileRepo.createProfile(
        name: 'Personal Expenses',
        type: ProfileType.expense,
        currencyCode: 'INR',
        accountId: testAccountId,
      );

      expect(created.type, equals(ProfileType.expense));
      expect(created.isExpense, isTrue);
      expect(created.isLedger, isFalse);

      // 2. Verify raw Drift storage stores canonical value 'expense'
      final rawRow = await (db.select(db.companies)
            ..where((t) => t.id.equals(created.id)))
          .getSingle();
      expect(rawRow.mode, equals('expense'));

      // 3. Reload through DriftProfileRepository
      final accessibleProfiles = await profileRepo.getAccessibleProfiles(testAccountId);
      expect(accessibleProfiles.length, equals(1));
      final reloadedProfile = accessibleProfiles.first;
      expect(reloadedProfile.id, equals(created.id));
      expect(reloadedProfile.type, equals(ProfileType.expense));
      expect(reloadedProfile.isExpense, isTrue);
      expect(reloadedProfile.isLedger, isFalse);

      // 4. Reload through DriftLedgerRepository.getCompanies()
      final companies = await ledgerRepo.getCompanies();
      expect(companies.length, equals(1));
      final reloadedCompany = companies.first;
      expect(reloadedCompany.id, equals(created.id));
      expect(reloadedCompany.mode, equals(CompanyMode.expenseTracker));
      expect(reloadedCompany.isExpense, isTrue);
      expect(reloadedCompany.isLedger, isFalse);
    });

    test('2. An Expense profile remains Expense after Supabase serialization and deserialization', () {
      final now = DateTime.utc(2026, 11, 8, 12, 0, 0);
      final expenseCompany = Company(
        id: 'cmp_expense_1',
        name: 'My Personal Wallet',
        legalName: 'My Personal Wallet',
        mode: CompanyMode.expenseTracker,
        currencyCode: 'USD',
        createdAt: now,
        updatedAt: now,
      );

      // Serialize to wire payload (as sent to Supabase / outbox)
      final serializedPayload = expenseCompany.toMap();

      // Canonical wire value MUST be 'expense'
      expect(serializedPayload['mode'], equals('expense'));

      // Deserialize payload (as received from Supabase / sync pull)
      final restoredCompany = Company.fromMap(serializedPayload);

      expect(restoredCompany.id, equals(expenseCompany.id));
      expect(restoredCompany.mode, equals(CompanyMode.expenseTracker));
      expect(restoredCompany.isExpense, isTrue);
      expect(restoredCompany.isLedger, isFalse);
      expect(restoredCompany.mode.canonicalValue, equals('expense'));
    });

    test('3. A Ledger profile remains Ledger across database and serialization', () async {
      // 1. Create a Ledger profile
      final created = await profileRepo.createProfile(
        name: 'Enterprise Logistics',
        type: ProfileType.ledger,
        currencyCode: 'INR',
        legalName: 'Enterprise Logistics Pvt Ltd',
        gstin: '29ABCDE1234F1Z5',
        accountId: testAccountId,
      );

      expect(created.type, equals(ProfileType.ledger));
      expect(created.isLedger, isTrue);
      expect(created.isExpense, isFalse);

      // 2. Verify raw Drift storage stores canonical value 'ledger'
      final rawRow = await (db.select(db.companies)
            ..where((t) => t.id.equals(created.id)))
          .getSingle();
      expect(rawRow.mode, equals('ledger'));

      // 3. Reload through DriftProfileRepository
      final accessibleProfiles = await profileRepo.getAccessibleProfiles(testAccountId);
      final reloadedProfile = accessibleProfiles.firstWhere((p) => p.id == created.id);
      expect(reloadedProfile.type, equals(ProfileType.ledger));
      expect(reloadedProfile.isLedger, isTrue);
      expect(reloadedProfile.isExpense, isFalse);

      // 4. Reload through DriftLedgerRepository.getCompanies()
      final companies = await ledgerRepo.getCompanies();
      final reloadedCompany = companies.firstWhere((c) => c.id == created.id);
      expect(reloadedCompany.mode, equals(CompanyMode.ledger));
      expect(reloadedCompany.isLedger, isTrue);
      expect(reloadedCompany.isExpense, isFalse);

      // 5. Serialize and deserialize
      final map = reloadedCompany.toMap();
      expect(map['mode'], equals('ledger'));

      final restored = Company.fromMap(map);
      expect(restored.mode, equals(CompanyMode.ledger));
      expect(restored.isLedger, isTrue);
      expect(restored.isExpense, isFalse);
    });

    test('4. Legacy Expense values are parsed correctly without losing Expense identity', () {
      final legacyExpenseInputs = [
        'expense',
        'expenseTracker',
        'expense_tracker',
        'EXPENSE',
        'EXPENSETRACKER',
        'Expense_Tracker',
        ' expense ',
        'expense-tracker',
      ];

      for (final input in legacyExpenseInputs) {
        // CompanyMode parser
        expect(
          CompanyMode.fromName(input),
          equals(CompanyMode.expenseTracker),
          reason: 'Failed to parse legacy CompanyMode: $input',
        );

        // ProfileType parser
        expect(
          ProfileType.fromString(input),
          equals(ProfileType.expense),
          reason: 'Failed to parse legacy ProfileType: $input',
        );

        // Company.fromMap with legacy payload
        final company = Company.fromMap({
          'id': 'cmp_legacy_$input',
          'name': 'Legacy Company',
          'legalName': 'Legacy Company',
          'mode': input,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        });
        expect(
          company.mode,
          equals(CompanyMode.expenseTracker),
          reason: 'Company.fromMap failed for mode: $input',
        );
        expect(company.isExpense, isTrue);
      }
    });

    test('5. Unknown profile types do not silently become Ledger', () {
      final unknownInputs = [
        'unknown',
        'crypto_wallet',
        'savings_pool',
        'ledger_pro',
        'random_string_123',
        '',
        '   ',
      ];

      for (final input in unknownInputs) {
        // CompanyMode.fromName MUST throw UnknownProfileTypeException
        expect(
          () => CompanyMode.fromName(input),
          throwsA(isA<UnknownProfileTypeException>()),
          reason: 'CompanyMode silently accepted unknown input: "$input"',
        );

        // ProfileType.fromString MUST throw UnknownProfileTypeException
        expect(
          () => ProfileType.fromString(input),
          throwsA(isA<UnknownProfileTypeException>()),
          reason: 'ProfileType silently accepted unknown input: "$input"',
        );

        // Company.fromMap MUST throw UnknownProfileTypeException
        expect(
          () => Company.fromMap({
            'id': 'c_bad',
            'name': 'Bad Co',
            'legalName': 'Bad Co',
            'mode': input,
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          }),
          throwsA(isA<UnknownProfileTypeException>()),
          reason: 'Company.fromMap silently accepted unknown input: "$input"',
        );
      }

      // Null mode explicitly present in map throws
      expect(
        () => CompanyMode.fromName(null),
        throwsA(isA<UnknownProfileTypeException>()),
      );
      expect(
        () => ProfileType.fromString(null),
        throwsA(isA<UnknownProfileTypeException>()),
      );
      expect(
        () => Company.fromMap({
          'id': 'c_null',
          'name': 'Null Co',
          'legalName': 'Null Co',
          'mode': null,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        }),
        throwsA(isA<UnknownProfileTypeException>()),
      );
    });

    test('6. Profile switching preserves each profile\'s original type', () async {
      // 1. Create one Expense profile and one Ledger profile
      final expProfile = await profileRepo.createProfile(
        name: 'Household Budget',
        type: ProfileType.expense,
        accountId: testAccountId,
      );

      final ledProfile = await profileRepo.createProfile(
        name: 'Retail Store',
        type: ProfileType.ledger,
        accountId: testAccountId,
      );

      final mockAuth = MockAuthRepository(
        isAuthenticated: true,
        userId: testAccountId,
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(syncEngine),
          driftLedgerRepositoryProvider.overrideWithValue(ledgerRepo),
          profileRepositoryProvider.overrideWithValue(profileRepo),
        ],
      );
      addTearDown(container.dispose);

      final sessionController = container.read(profileSessionProvider.notifier);

      // 2. Let initial build() microtask finish loading profiles
      await pumpEventQueue();

      final sessionState = container.read(profileSessionProvider);
      expect(sessionState, isA<ProfileSelectionRequiredSessionState>());
      final selectionState = sessionState as ProfileSelectionRequiredSessionState;
      expect(selectionState.profiles.length, equals(2));

      // 3. Switch to Expense profile
      sessionController.switchProfile(expProfile);
      await pumpEventQueue();

      final currentSession1 = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(currentSession1.activeProfile.id, equals(expProfile.id));
      expect(currentSession1.activeProfile.type, equals(ProfileType.expense));
      expect(currentSession1.activeProfile.isExpense, isTrue);

      await container.read(companiesProvider.future);
      final activeCompany1 = container.read(activeCompanyProvider);
      expect(activeCompany1.id, equals(expProfile.id));
      expect(activeCompany1.mode, equals(CompanyMode.expenseTracker));
      expect(activeCompany1.isExpense, isTrue);
      expect(activeCompany1.isLedger, isFalse);

      // 4. Switch to Ledger profile
      sessionController.switchProfile(ledProfile);
      await pumpEventQueue();

      final currentSession2 = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(currentSession2.activeProfile.id, equals(ledProfile.id));
      expect(currentSession2.activeProfile.type, equals(ProfileType.ledger));
      expect(currentSession2.activeProfile.isLedger, isTrue);

      final activeCompany2 = container.read(activeCompanyProvider);
      expect(activeCompany2.id, equals(ledProfile.id));
      expect(activeCompany2.mode, equals(CompanyMode.ledger));
      expect(activeCompany2.isLedger, isTrue);
      expect(activeCompany2.isExpense, isFalse);

      // 5. Switch back to Expense profile
      sessionController.switchProfile(expProfile);
      await pumpEventQueue();

      final currentSession3 = container.read(profileSessionProvider) as ActiveProfileReadySessionState;
      expect(currentSession3.activeProfile.id, equals(expProfile.id));
      expect(currentSession3.activeProfile.type, equals(ProfileType.expense));

      final activeCompany3 = container.read(activeCompanyProvider);
      expect(activeCompany3.id, equals(expProfile.id));
      expect(activeCompany3.mode, equals(CompanyMode.expenseTracker));
      expect(activeCompany3.isExpense, isTrue);
      expect(activeCompany3.isLedger, isFalse);
    });

    test('7. Profile type is immutable after creation and cannot be changed via copyWith', () {
      final now = DateTime.now();
      final expenseCompany = Company(
        id: 'c_exp_imm',
        name: 'Expense Profile',
        legalName: 'Expense Profile',
        mode: CompanyMode.expenseTracker,
        createdAt: now,
        updatedAt: now,
      );

      final ledgerCompany = Company(
        id: 'c_led_imm',
        name: 'Ledger Profile',
        legalName: 'Ledger Profile',
        mode: CompanyMode.ledger,
        createdAt: now,
        updatedAt: now,
      );

      // Modifying non-type fields works
      final renamed = expenseCompany.copyWith(name: 'Updated Expense Name');
      expect(renamed.name, equals('Updated Expense Name'));
      expect(renamed.mode, equals(CompanyMode.expenseTracker));

      // Attempting to change Expense -> Ledger throws StateError
      expect(
        () => expenseCompany.copyWith(mode: CompanyMode.ledger),
        throwsA(isA<StateError>()),
      );

      // Attempting to change Ledger -> Expense throws StateError
      expect(
        () => ledgerCompany.copyWith(mode: CompanyMode.expenseTracker),
        throwsA(isA<StateError>()),
      );
    });
  });
}
