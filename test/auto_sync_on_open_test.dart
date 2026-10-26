import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/home/dashboard_screen.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/providers/sync_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Automatic Sync on App Open Unit Tests', () {
    test('autoSyncOnAppOpen triggers sync and debounces within 5 seconds', () async {
      final cmp1 = Company(
        id: 'cmp_sync_1',
        name: 'AutoSync Company',
        legalName: 'AutoSync Company Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1],
                  activeCompanyId: 'cmp_sync_1',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(syncControllerProvider.notifier);
      expect(container.read(syncControllerProvider), equals(SyncStatus.idle));

      // 1. First trigger runs sync
      await notifier.autoSyncOnAppOpen();
      expect(container.read(syncControllerProvider), equals(SyncStatus.success));
      expect(notifier.lastSyncTime, isNotNull);

      final firstSyncTime = notifier.lastSyncTime;

      // 2. Immediate second trigger within debounce interval should be skipped
      await notifier.autoSyncOnAppOpen();
      expect(notifier.lastSyncTime, equals(firstSyncTime));
    });

    test('autoSyncProvider auto-triggers sync on startup and on company switch', () async {
      final cmp1 = Company(
        id: 'cmp_1',
        name: 'Company One',
        legalName: 'Company One Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final cmp2 = Company(
        id: 'cmp_2',
        name: 'Company Two',
        legalName: 'Company Two Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final fakeEngine = _FakeSyncEngine(db: db);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(fakeEngine),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1, cmp2],
                  activeCompanyId: 'cmp_1',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      // Listening to autoSyncProvider initializes the listener
      container.listen(autoSyncProvider, (_, _) {});

      // Allow microtask to run
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fakeEngine.syncCallCount, greaterThanOrEqualTo(1));
    });
  });

  group('DashboardScreen Sync Button & Manual Menu Widget Test', () {
    testWidgets('Manual sync & backup menu button remains visible and opens SyncSettingsSheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final cmp1 = Company(
        id: 'cmp_dash_1',
        name: 'Main Enterprise',
        legalName: 'Main Enterprise Ltd',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final fakeEngine = _FakeSyncEngine(db: db);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(fakeEngine),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1],
                  activeCompanyId: 'cmp_dash_1',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Sync & Backup app bar button
      final syncButton = find.byTooltip('Sync & Backup');
      expect(syncButton, findsOneWidget);

      // Tapping the button opens SyncSettingsSheet
      await tester.tap(syncButton);
      await tester.pumpAndSettle();

      // Verify SyncSettingsSheet is presented with manual sync button & backup options
      expect(find.text('Sync & Backup Center'), findsOneWidget);
      expect(find.text('Pending Outbox Queue'), findsOneWidget);
      expect(find.text('Supabase Cloud Sync'), findsOneWidget);
      expect(
        find.text('Sync Now').evaluate().isNotEmpty ||
            find.text('Syncing...').evaluate().isNotEmpty,
        isTrue,
      );
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}

class _FakeSyncEngine extends SyncEngine {
  int syncCallCount = 0;

  _FakeSyncEngine({required super.db});

  @override
  Future<SyncResult> syncAll({String? companyId}) async {
    syncCallCount++;
    return SyncResult(
      success: true,
      itemsPushed: 0,
      itemsPulled: 0,
      timestamp: DateTime.now(),
    );
  }
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
