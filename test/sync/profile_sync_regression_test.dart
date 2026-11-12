import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_codec.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/providers/auth_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/strict_fake_remote.dart';

class _FakeAuthController extends AuthController {
  final String _userId;
  final String _phone;

  _FakeAuthController({String userId = 'usr_reg_1', String phone = '+91 98765 43210'})
      : _userId = userId,
        _phone = phone;

  @override
  AuthState build() {
    return AuthState(
      isAuthenticated: true,
      userId: _userId,
      phoneNumber: _phone,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Profile & Company Synchronization Regression Tests', () {
    late AppDatabase dbA;
    late SyncEngine syncEngineA;
    late DriftLedgerRepository repoA;
    late StrictFakeRemoteSyncBackend fakeRemote;
    const testUserId = '00000000-0000-4000-8000-000000000001';
    const companyId = 'cmp_reg_workspace_1';

    setUp(() {
      dbA = AppDatabase(NativeDatabase.memory());
      fakeRemote = StrictFakeRemoteSyncBackend();
      syncEngineA = SyncEngine(
        db: dbA,
        activeUserId: testUserId,
        fakeRemoteStore: fakeRemote,
        simulateSyncForTesting: true,
      );
      repoA = DriftLedgerRepository(
        db: dbA,
        syncEngine: syncEngineA,
        autoSync: false,
        currentCompanyId: companyId,
        currentUserId: testUserId,
      );
    });

    tearDown(() async {
      repoA.dispose();
      syncEngineA.dispose();
      await dbA.close();
    });

    test('Create profile and synchronize: validates clean payload without non-column fields', () async {
      final comp = Company(
        id: companyId,
        name: 'Apex Innovations',
        legalName: 'Apex Innovations Pvt Ltd',
        gstin: '29ABCDE1234F1Z5',
        currencyCode: 'INR',
        address: '100 Feet Rd, Indiranagar, Bangalore',
        email: 'contact@apex.io',
        phoneNumber: '+91 98765 00001',
        bankName: 'HDFC Bank',
        bankAccountNumber: '50200012345678',
        bankIfsc: 'HDFC0001234',
        upiId: 'apex@hdfc',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final profile = UserProfile(
        id: testUserId,
        name: 'Samir Navas',
        phoneNumber: '+91 98765 00001',
        email: 'samir@apex.io',
        businessName: 'Apex Innovations',
        address: '100 Feet Rd, Indiranagar, Bangalore',
        gstin: '29ABCDE1234F1Z5',
        businessType: 'Software & Technology',
        bankName: 'HDFC Bank',
        bankAccountNumber: '50200012345678',
        bankIfsc: 'HDFC0001234',
        upiId: 'apex@hdfc',
        companies: [comp],
        activeCompanyId: companyId,
        role: Role.admin,
      );

      await repoA.saveUserProfile(profile);

      // Verify outbox entry was recorded for user_profiles
      final outboxItems = await (dbA.select(dbA.syncOutbox)
            ..where((t) => t.recordId.equals(testUserId) & t.targetTable.equals('user_profiles')))
          .get();
      expect(outboxItems.length, equals(1));

      // Verify push succeeded without PGRST204 errors
      final pushRes = await syncEngineA.pushQueue(companyId: companyId);
      expect(pushRes.success, isTrue);

      // Verify remote store received the profile with banking details and active_company_id
      final remoteRow = fakeRemote.getRow('user_profiles', testUserId);
      expect(remoteRow, isNotNull);
      expect(remoteRow!['name'], equals('Samir Navas'));
      expect(remoteRow['business_name'], equals('Apex Innovations'));
      expect(remoteRow['business_type'], equals('Software & Technology'));
      expect(remoteRow['bank_name'], equals('HDFC Bank'));
      expect(remoteRow['bank_account_number'], equals('50200012345678'));
      expect(remoteRow['bank_ifsc'], equals('HDFC0001234'));
      expect(remoteRow['upi_id'], equals('apex@hdfc'));
      expect(remoteRow['active_company_id'], equals(companyId));

      // Ensure invalid columns (companies, company_roles, company_id) were NOT sent to remote
      expect(remoteRow.containsKey('companies'), isFalse);
      expect(remoteRow.containsKey('company_roles'), isFalse);
      expect(remoteRow.containsKey('company_id'), isFalse);
    });

    test('Update profile information persists locally immediately and synchronizes to cloud', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(dbA),
          syncEngineProvider.overrideWithValue(syncEngineA),
          sharedPreferencesProvider.overrideWithValue(prefs),
          ledgerRepositoryProvider.overrideWithValue(repoA),
          driftLedgerRepositoryProvider.overrideWithValue(repoA),
          authControllerProvider.overrideWith(() => _FakeAuthController(userId: testUserId)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(userProfileProvider.notifier);
      final currentProfile = container.read(userProfileProvider);

      final updatedProfile = currentProfile.copyWith(
        id: testUserId,
        name: 'Samir Navas Updated',
        businessName: 'Apex Prime Technologies',
        address: 'MG Road, Bangalore',
        gstin: '29XYZAB5678C1D2',
        businessType: 'IT Consulting & Services',
        bankName: 'State Bank of India',
        bankAccountNumber: '998877665544',
        bankIfsc: 'SBIN0005678',
        upiId: 'apexprime@sbi',
        activeCompanyId: companyId,
      );

      notifier.updateProfile(updatedProfile);

      // Verify local database updated immediately with pending status
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final localRow = await (dbA.select(dbA.userProfiles)..where((t) => t.id.equals(testUserId))).getSingle();
      expect(localRow.name, equals('Samir Navas Updated'));
      expect(localRow.businessName, equals('Apex Prime Technologies'));
      expect(localRow.bankName, equals('State Bank of India'));
      expect(localRow.syncStatus, equals(SyncRecordStatus.pending));

      // Synchronize
      final pushRes = await syncEngineA.pushQueue(companyId: companyId);
      expect(pushRes.success, isTrue);

      final remoteRow = fakeRemote.getRow('user_profiles', testUserId);
      expect(remoteRow, isNotNull);
      expect(remoteRow!['name'], equals('Samir Navas Updated'));
      expect(remoteRow['business_name'], equals('Apex Prime Technologies'));
      expect(remoteRow['bank_name'], equals('State Bank of India'));
      expect(remoteRow['bank_account_number'], equals('998877665544'));
    });

    test('Pull profile on another device (Device B) restores complete profile without data loss', () async {
      // 1. Populate remote backend with complete user profile
      fakeRemote.upsert('user_profiles', testUserId, {
        'id': testUserId,
        'name': 'Cloud User',
        'phone_number': '+91 99999 11111',
        'email': 'cloud@ledgerpulse.io',
        'business_name': 'Cloud Ventures',
        'address': 'Koramangala, Bangalore',
        'gstin': '29ABCDE0000Z1Z1',
        'business_type': 'Venture Studio',
        'bank_name': 'Kotak Mahindra Bank',
        'bank_account_number': '1122334455',
        'bank_ifsc': 'KKBK0001234',
        'upi_id': 'cloud@kotak',
        'active_company_id': 'cmp_cloud_workspace',
        'role': 'admin',
        'is_deleted': false,
        'updated_at': encodeTime(DateTime.now()),
      });

      fakeRemote.upsert('companies', 'cmp_cloud_workspace', {
        'id': 'cmp_cloud_workspace',
        'name': 'Cloud Ventures',
        'legal_name': 'Cloud Ventures Pvt Ltd',
        'gstin': '29ABCDE0000Z1Z1',
        'address': 'Koramangala, Bangalore',
        'mode': 'ledger',
        'currency_code': 'INR',
        'owner_id': testUserId,
        'is_deleted': false,
        'updated_at': encodeTime(DateTime.now()),
      });

      // 2. Device B fresh setup
      final dbB = AppDatabase(NativeDatabase.memory());
      final syncEngineB = SyncEngine(
        db: dbB,
        activeUserId: testUserId,
        fakeRemoteStore: fakeRemote,
        simulateSyncForTesting: true,
      );

      // 3. Pull on Device B
      final pullRes = await syncEngineB.pullChanges(companyId: 'cmp_cloud_workspace');
      expect(pullRes.success, isTrue);

      // 4. Verify local DB on Device B contains all fields
      final pulledProfile = await (dbB.select(dbB.userProfiles)..where((t) => t.id.equals(testUserId))).getSingleOrNull();
      expect(pulledProfile, isNotNull);
      expect(pulledProfile!.name, equals('Cloud User'));
      expect(pulledProfile.businessName, equals('Cloud Ventures'));
      expect(pulledProfile.businessType, equals('Venture Studio'));
      expect(pulledProfile.bankName, equals('Kotak Mahindra Bank'));
      expect(pulledProfile.bankAccountNumber, equals('1122334455'));
      expect(pulledProfile.bankIfsc, equals('KKBK0001234'));
      expect(pulledProfile.upiId, equals('cloud@kotak'));
      expect(pulledProfile.activeCompanyId, equals('cmp_cloud_workspace'));
      expect(pulledProfile.syncStatus, equals(SyncRecordStatus.synced));

      syncEngineB.dispose();
      await dbB.close();
    });

    test('Repeated synchronization is idempotent and creates no duplicate records', () async {
      final comp = Company(
        id: 'cmp_idem_1',
        name: 'Idempotent Workspace',
        legalName: 'Idempotent Workspace Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final profile = UserProfile(
        id: testUserId,
        name: 'Idem User',
        phoneNumber: '+91 90000 00000',
        email: 'idem@ledgerpulse.io',
        companies: [comp],
        activeCompanyId: comp.id,
      );

      await repoA.saveUserProfile(profile);

      // Push 1
      final push1 = await syncEngineA.pushQueue(companyId: comp.id);
      expect(push1.success, isTrue);

      // Push 2 immediately (idempotent, nothing new to push)
      final push2 = await syncEngineA.pushQueue(companyId: comp.id);
      expect(push2.success, isTrue);
      expect(push2.itemsPushed, equals(0));

      // Pull 1
      final pull1 = await syncEngineA.pullChanges(companyId: comp.id);
      expect(pull1.success, isTrue);

      // Pull 2
      final pull2 = await syncEngineA.pullChanges(companyId: comp.id);
      expect(pull2.success, isTrue);

      // Check record counts
      final profCount = await (dbA.select(dbA.userProfiles)..where((t) => t.id.equals(testUserId))).get();
      expect(profCount.length, equals(1));

      final compCount = await (dbA.select(dbA.companies)..where((t) => t.id.equals(comp.id))).get();
      expect(compCount.length, equals(1));
    });

    test('Offline changes remain queued and synchronize when connectivity returns', () async {
      // 1. Simulate offline network error
      fakeRemote.simulateNetworkError = true;

      final comp = Company(
        id: 'cmp_offline_1',
        name: 'Offline Co',
        legalName: 'Offline Co Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final profile = UserProfile(
        id: testUserId,
        name: 'Offline User',
        phoneNumber: '+91 91111 22222',
        email: 'offline@ledgerpulse.io',
        companies: [comp],
        activeCompanyId: comp.id,
      );

      await repoA.saveUserProfile(profile);

      // Attempt push while offline
      final failedPush = await syncEngineA.pushQueue(companyId: comp.id);
      expect(failedPush.success, isFalse);

      // Verify outbox retains mutations
      final pendingCount = await syncEngineA.getPendingCount();
      expect(pendingCount, greaterThan(0));

      // Verify local sync status remains pending
      final profRow = await (dbA.select(dbA.userProfiles)..where((t) => t.id.equals(testUserId))).getSingle();
      expect(profRow.syncStatus, equals(SyncRecordStatus.pending));

      // 2. Connectivity returns
      fakeRemote.simulateNetworkError = false;

      // Retry push
      final successPush = await syncEngineA.pushQueue(companyId: comp.id);
      expect(successPush.success, isTrue);

      // Outbox clears
      final finalPending = await syncEngineA.getPendingCount();
      expect(finalPending, equals(0));

      // Status marked synced
      final syncedRow = await (dbA.select(dbA.userProfiles)..where((t) => t.id.equals(testUserId))).getSingle();
      expect(syncedRow.syncStatus, equals(SyncRecordStatus.synced));
    });

    test('Stale remote data cannot overwrite newer local pending changes', () async {
      // 1. Setup existing synced profile in local DB and remote
      final baseDate = DateTime(2026, 11, 1, 10, 0);
      fakeRemote.upsert('user_profiles', testUserId, {
        'id': testUserId,
        'name': 'Stale Remote Name',
        'phone_number': '+91 99999 88888',
        'email': 'remote@example.com',
        'business_name': 'Old Remote Business',
        'updated_at': encodeTime(baseDate),
      });

      await (dbA.into(dbA.userProfiles)).insert(
        UserProfilesCompanion.insert(
          id: testUserId,
          name: 'Local Edited Name',
          phoneNumber: '+91 99999 88888',
          email: 'local@example.com',
          businessName: const Value('Newer Local Business'),
          activeCompanyId: const Value(companyId),
          updatedAt: Value(DateTime(2026, 11, 12, 14, 0)),
          syncStatus: const Value(SyncRecordStatus.pending), // Pending local change
        ),
      );

      // 2. Pull remote changes
      final pullRes = await syncEngineA.pullChanges(companyId: companyId);
      expect(pullRes.success, isTrue);

      // 3. Verify that local pending change was PRESERVED and not overwritten by stale remote data
      final localRow = await (dbA.select(dbA.userProfiles)..where((t) => t.id.equals(testUserId))).getSingle();
      expect(localRow.name, equals('Local Edited Name'));
      expect(localRow.businessName, equals('Newer Local Business'));
      expect(localRow.syncStatus, equals(SyncRecordStatus.pending));
    });
  });
}

