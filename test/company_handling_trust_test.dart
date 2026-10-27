import 'dart:convert';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';

class FailingDriftLedgerRepository extends DriftLedgerRepository {
  FailingDriftLedgerRepository({required super.db, super.syncEngine, super.postingEngine});

  @override
  Future<Company> createCompany(
    Company company, {
    Map<String, int>? initialWalletBalancesInCents,
  }) async {
    throw Exception('Simulated DB Failure on createCompany');
  }

  @override
  Future<Company> updateCompany(Company company) async {
    throw Exception('Simulated DB Failure on updateCompany');
  }

  @override
  Future<void> deleteCompany(String companyId) async {
    throw Exception('Simulated DB Failure on deleteCompany');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SyncEngine syncEngine;
  late DriftLedgerRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    syncEngine = SyncEngine(db: db, simulateSyncForTesting: true);
    repo = DriftLedgerRepository(db: db, syncEngine: syncEngine, autoSync: false);
  });

  tearDown(() async {
    repo.dispose();
    syncEngine.dispose();
    await db.close();
  });

  group('Company Handling Trustworthiness Tests', () {
    test('failed DB write leaves state unchanged and reports error', () async {
      final initialCompany = Company(
        id: 'cmp_existing',
        name: 'Safe Haven Inc',
        legalName: 'Safe Haven Inc Ltd',
        gstin: '29ABCDE1234F1Z5',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final failingRepo = FailingDriftLedgerRepository(db: db);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          driftLedgerRepositoryProvider.overrideWithValue(failingRepo),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Owner',
                  phoneNumber: '+91 99999 11111',
                  email: 'owner@example.com',
                  companies: [initialCompany],
                  activeCompanyId: 'cmp_existing',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(companyControllerProvider.notifier);

      // 1. Failed addCompany leaves state unchanged and throws
      final newComp = Company(
        id: 'cmp_failed_new',
        name: 'Should Not Exist Corp',
        legalName: 'Should Not Exist Corp',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(
        () => controller.addCompany(newComp),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Simulated DB Failure on createCompany'))),
      );

      // Verify state was not modified
      expect(container.read(userCompaniesProvider).length, equals(1));
      expect(container.read(userCompaniesProvider).first.id, equals('cmp_existing'));
      expect(container.read(activeCompanyProvider).id, equals('cmp_existing'));

      // 2. Failed updateCompany leaves state unchanged and throws
      final updatedComp = initialCompany.copyWith(name: 'Malicious Update Name');
      expect(
        () => controller.updateCompany(updatedComp),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Simulated DB Failure on updateCompany'))),
      );

      expect(container.read(activeCompanyProvider).name, equals('Safe Haven Inc'));
      expect(container.read(userCompaniesProvider).first.name, equals('Safe Haven Inc'));

      // 3. Failed deleteCompany leaves state unchanged and throws
      final comp2 = Company(
        id: 'cmp_second',
        name: 'Second Company',
        legalName: 'Second Company',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      container.read(userProfileProvider.notifier).updateProfile(
            container.read(userProfileProvider).copyWith(companies: [initialCompany, comp2]),
          );
      expect(container.read(userCompaniesProvider).length, equals(2));

      expect(
        () => controller.deleteCompany('cmp_second'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Simulated DB Failure on deleteCompany'))),
      );

      expect(container.read(userCompaniesProvider).length, equals(2));
      expect(container.read(userCompaniesProvider).any((c) => c.id == 'cmp_second'), isTrue);
    });

    test('editing the active company updates activeCompanyProvider', () async {
      final repo = DriftLedgerRepository(db: db);
      final cmp = Company(
        id: 'cmp_active_edit',
        name: 'Original Active Co',
        legalName: 'Original Active Legal',
        gstin: '29ABCDE1234F1Z9',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.createCompany(cmp);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Admin',
                  phoneNumber: '+91 99999 00000',
                  email: 'admin@example.com',
                  activeCompanyId: 'cmp_active_edit',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      // Force companiesProvider to resolve
      final loadedCompanies = await container.read(companiesProvider.future);
      expect(loadedCompanies.length, equals(1));
      expect(container.read(activeCompanyProvider).name, equals('Original Active Co'));

      // Edit active company
      final controller = container.read(companyControllerProvider.notifier);
      final updated = cmp.copyWith(
        name: 'Apex Global Enterprises',
        legalName: 'Apex Global Enterprises Pvt Ltd',
      );
      await controller.updateCompany(updated);

      // Wait for repository update stream and invalidation
      await container.read(companiesProvider.future);

      final currentActive = container.read(activeCompanyProvider);
      expect(currentActive.name, equals('Apex Global Enterprises'));
      expect(currentActive.legalName, equals('Apex Global Enterprises Pvt Ltd'));
    });

    test('profile edits do not recreate the ledger repository', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(syncEngine),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // 1. Initial read of ledgerRepositoryProvider
      final initialRepo = container.read(ledgerRepositoryProvider);

      // 2. Edit profile fields (name, email, phoneNumber, businessType)
      final notifier = container.read(userProfileProvider.notifier);
      final currentProfile = container.read(userProfileProvider);
      notifier.updateProfile(
        currentProfile.copyWith(
          name: 'Completely New Name',
          email: 'newemail@example.com',
          phoneNumber: '+91 88888 77777',
          businessType: 'Manufacturing',
        ),
      );

      // 3. Read ledgerRepositoryProvider again
      final repoAfterProfileEdit = container.read(ledgerRepositoryProvider);

      // Must be identical because activeCompanyId, userId, and role did not change
      expect(identical(initialRepo, repoAfterProfileEdit), isTrue);

      // 4. Changing activeCompanyId SHOULD trigger rebuild
      notifier.updateProfile(
        container.read(userProfileProvider).copyWith(activeCompanyId: 'cmp_switched_id'),
      );
      final repoAfterCompanySwitch = container.read(ledgerRepositoryProvider);
      expect(identical(initialRepo, repoAfterCompanySwitch), isFalse);

      // Await async profile saves so database transaction finishes cleanly
      await notifier.syncProfileToDatabase();
    });

    test('new company gets its chart of accounts exactly once in transaction', () async {
      final repo = DriftLedgerRepository(db: db);
      final company = Company(
        id: 'cmp_new_chart_test',
        name: 'Charted Corp',
        legalName: 'Charted Corp Pvt Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Verify no accounts exist before creation
      final preAccounts = await (db.select(db.accounts)..where((t) => t.companyId.equals(company.id))).get();
      expect(preAccounts, isEmpty);

      // Create company
      await repo.createCompany(company);

      // Verify Chart of Accounts was seeded atomically
      final postAccounts = await (db.select(db.accounts)..where((t) => t.companyId.equals(company.id))).get();
      expect(postAccounts, isNotEmpty);
      final initialCount = postAccounts.length;

      // Call ensureCompanyAccounts again - it must verify and NOT duplicate accounts
      await repo.postingEngine.ensureCompanyAccounts(company.id);

      final secondAccounts = await (db.select(db.accounts)..where((t) => t.companyId.equals(company.id))).get();
      expect(secondAccounts.length, equals(initialCount));
    });

    test('companies created before this change still get accounts when first used', () async {
      final postingEngine = VoucherPostingEngine(db, AuditService(db));
      const legacyCompanyId = 'cmp_legacy_pre_existing';

      // Insert company directly without seeding accounts
      await db.into(db.companies).insert(
            CompaniesCompanion.insert(
              id: legacyCompanyId,
              name: 'Legacy Trading',
              legalName: 'Legacy Trading Co',
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // Verify zero accounts currently exist for legacy company
      final accountsBefore = await (db.select(db.accounts)..where((t) => t.companyId.equals(legacyCompanyId))).get();
      expect(accountsBefore, isEmpty);

      // When first used, ensureCompanyAccounts verifies and seeds missing accounts
      await postingEngine.ensureCompanyAccounts(legacyCompanyId);

      final accountsAfter = await (db.select(db.accounts)..where((t) => t.companyId.equals(legacyCompanyId))).get();
      expect(accountsAfter, isNotEmpty);
      expect(accountsAfter.any((a) => a.name.contains('Cash') || a.name.contains('Bank')), isTrue);
    });

    test('one-time compatibility: imports companiesJson if Companies table has no companies', () async {
      final repo = DriftLedgerRepository(db: db);
      const importedCompId = 'cmp_imported_from_json';
      final legacyCompany = Company(
        id: importedCompId,
        name: 'Imported Enterprise',
        legalName: 'Imported Enterprise Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Insert UserProfile with companiesJson populated, but Companies table completely empty
      await db.into(db.userProfiles).insert(
            UserProfilesCompanion.insert(
              id: 'usr_legacy',
              name: 'Legacy User',
              phoneNumber: '+91 90000 00000',
              email: 'legacy@example.com',
              activeCompanyId: const Value(importedCompId),
              companiesJson: Value(jsonEncode([legacyCompany.toMap()])),
            ),
          );

      final preCompanies = await (db.select(db.companies)..where((t) => t.isDeleted.equals(false))).get();
      expect(preCompanies, isEmpty);

      // getCompanies triggers one-time import
      final loaded = await repo.getCompanies();
      expect(loaded.length, equals(1));
      expect(loaded.first.id, equals(importedCompId));
      expect(loaded.first.name, equals('Imported Enterprise'));

      // Verify it was persisted to Companies table
      final inTable = await (db.select(db.companies)..where((t) => t.isDeleted.equals(false))).get();
      expect(inTable.length, equals(1));
      expect(inTable.first.name, equals('Imported Enterprise'));

      // Subsequent saveUserProfile must NOT write companiesJson
      final profile = await repo.getUserProfile('usr_legacy');
      expect(profile, isNotNull);
      await repo.saveUserProfile(profile!);

      final updatedProfileRow = await (db.select(db.userProfiles)..where((t) => t.id.equals('usr_legacy'))).getSingle();
      expect(updatedProfileRow.name, equals('Legacy User'));
    });
  });
}

class _TestUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestUserProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}
