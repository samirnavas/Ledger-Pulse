import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';

class _FakeAuthController extends AuthController {
  @override
  AuthState build() {
    return const AuthState(
      isAuthenticated: true,
      phoneNumber: '+91 98765 43210',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Company and Profile Database & Sync Tests', () {
    late AppDatabase db;
    late DriftLedgerRepository repo;
    late SyncEngine syncEngine;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      syncEngine = SyncEngine(db: db);
      repo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        autoSync: false,
        currentCompanyId: 'cmp_sync_test',
        currentUserId: 'usr_test_1',
      );
    });

    tearDown(() async {
      repo.dispose();
      syncEngine.dispose();
      await db.close();
    });

    test('Company creation writes to Companies table and enqueues to SyncOutbox', () async {
      final comp = Company(
        id: 'cmp_tech_corp',
        name: 'Tech Corp Global',
        legalName: 'Tech Corp Global Pvt Ltd',
        gstin: '29ABCDE9999F1Z5',
        currencyCode: 'INR',
        address: 'MG Road, Bangalore',
        email: 'info@techcorp.com',
        phoneNumber: '+91 91234 56789',
        bankName: 'HDFC Bank',
        bankAccountNumber: '50200012345678',
        bankIfsc: 'HDFC0001234',
        upiId: 'techcorp@hdfcbank',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(comp);

      // Verify local database row
      final row = await (db.select(db.companies)..where((t) => t.id.equals('cmp_tech_corp'))).getSingle();
      expect(row.name, equals('Tech Corp Global'));
      expect(row.gstin, equals('29ABCDE9999F1Z5'));
      expect(row.bankName, equals('HDFC Bank'));
      expect(row.upiId, equals('techcorp@hdfcbank'));
      expect(row.syncStatus, equals(SyncRecordStatus.pending));

      // Verify outbox queue
      final outboxItems = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('cmp_tech_corp'))).get();
      expect(outboxItems.length, equals(1));
      expect(outboxItems.first.targetTable, equals('companies'));
      expect(outboxItems.first.mutationType, equals('UPSERT'));
    });

    test('UserProfile saving persists to UserProfiles & Companies and enqueues to SyncOutbox', () async {
      final comp1 = Company(
        id: 'cmp_retail_1',
        name: 'Retail One',
        legalName: 'Retail One Enterprises',
        gstin: '29ABCDE1111F1Z1',
        address: 'Indiranagar, Bangalore',
        phoneNumber: '+91 98888 11111',
        bankName: 'ICICI Bank',
        bankAccountNumber: '000123456789',
        bankIfsc: 'ICIC0000001',
        upiId: 'alex@icici',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final profile = UserProfile(
        id: 'usr_test_1',
        name: 'Alex Mercer',
        phoneNumber: '+91 98888 11111',
        email: 'alex@example.com',
        businessName: 'Retail One',
        address: 'Indiranagar, Bangalore',
        gstin: '29ABCDE1111F1Z1',
        businessType: 'Wholesale & Retail',
        bankName: 'ICICI Bank',
        bankAccountNumber: '000123456789',
        bankIfsc: 'ICIC0000001',
        upiId: 'alex@icici',
        companies: [comp1],
        activeCompanyId: 'cmp_retail_1',
        role: Role.admin,
      );

      await repo.saveUserProfile(profile);

      // Verify Profile row in DB
      final profRow = await (db.select(db.userProfiles)..where((t) => t.id.equals('usr_test_1'))).getSingle();
      expect(profRow.name, equals('Alex Mercer'));
      expect(profRow.email, equals('alex@example.com'));
      expect(profRow.businessName, equals('Retail One'));
      expect(profRow.bankName, equals('ICICI Bank'));

      // Verify Company row in DB
      final compRow = await (db.select(db.companies)..where((t) => t.id.equals('cmp_retail_1'))).getSingle();
      expect(compRow.name, equals('Retail One'));

      // Verify Outbox contains records for both
      final outbox = await db.select(db.syncOutbox).get();
      expect(outbox.any((o) => o.targetTable == 'user_profiles' && o.recordId == 'usr_test_1'), isTrue);
      expect(outbox.any((o) => o.targetTable == 'companies' && o.recordId == 'cmp_retail_1'), isTrue);
    });

    test('SyncEngine processes and pushes company and user profile outbox items', () async {
      final comp = Company(
        id: 'cmp_push_test',
        name: 'Push Test Co',
        legalName: 'Push Test Co Pvt Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.createCompany(comp);

      final profile = UserProfile(
        id: 'usr_push_test',
        name: 'Jordan Belfort',
        phoneNumber: '+91 99999 00000',
        email: 'jordan@example.com',
        companies: [comp],
        activeCompanyId: 'cmp_push_test',
      );
      await repo.saveUserProfile(profile);

      // Verify outbox has items
      final pendingCountBefore = await syncEngine.getPendingCount();
      expect(pendingCountBefore, greaterThanOrEqualTo(2));

      // Push queue (offline simulation or remote push)
      final pushResult = await syncEngine.pushQueue();
      expect(pushResult.success, isTrue);
      expect(pushResult.itemsPushed, greaterThanOrEqualTo(2));

      // Verify outbox cleared
      final pendingCountAfter = await syncEngine.getPendingCount();
      expect(pendingCountAfter, equals(0));

      // Verify sync status updated to synced
      final compRow = await (db.select(db.companies)..where((t) => t.id.equals('cmp_push_test'))).getSingle();
      expect(compRow.syncStatus, equals(SyncRecordStatus.synced));

      final profRow = await (db.select(db.userProfiles)..where((t) => t.id.equals('usr_push_test'))).getSingle();
      expect(profRow.syncStatus, equals(SyncRecordStatus.synced));
    });

    test('UserProfileNotifier loads and persists profile to database via Riverpod', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(syncEngine),
          authControllerProvider.overrideWith(() => _FakeAuthController()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(userProfileProvider.notifier);
      final initial = container.read(userProfileProvider);
      expect(initial.name, isNotEmpty);

      final updated = initial.copyWith(
        name: 'Samir Pro Navas',
        businessName: 'Ledger Pulse Pro Global',
        bankName: 'State Bank of India',
        bankAccountNumber: '12345678901',
        bankIfsc: 'SBIN0001234',
        upiId: 'samir@sbi',
      );

      notifier.updateProfile(updated);

      expect(container.read(userProfileProvider).name, equals('Samir Pro Navas'));
      expect(container.read(userProfileProvider).businessName, equals('Ledger Pulse Pro Global'));

      // Verify persisted in DB
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final row = await (db.select(db.userProfiles)..where((t) => t.id.equals(updated.id))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.name, equals('Samir Pro Navas'));
      expect(row.businessName, equals('Ledger Pulse Pro Global'));
    });

    test('IsProfileEditingNotifier and ProfileSaveActionNotifier manage FAB state smoothly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isProfileEditingProvider), isFalse);
      expect(container.read(hasProfileChangesProvider), isFalse);
      expect(container.read(profileSaveActionProvider), isNull);

      container.read(isProfileEditingProvider.notifier).setEditing(true);
      expect(container.read(isProfileEditingProvider), isTrue);

      container.read(hasProfileChangesProvider.notifier).setHasChanges(true);
      expect(container.read(hasProfileChangesProvider), isTrue);

      bool saveCalled = false;
      container.read(profileSaveActionProvider.notifier).setAction(() {
        saveCalled = true;
      });

      expect(container.read(profileSaveActionProvider), isNotNull);
      container.read(profileSaveActionProvider)?.call();
      expect(saveCalled, isTrue);

      container.read(isProfileEditingProvider.notifier).setEditing(false);
      expect(container.read(isProfileEditingProvider), isFalse);
    });
  });
}

