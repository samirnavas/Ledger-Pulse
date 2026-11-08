import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/network/sync_codec.dart';
import '../../core/network/sync_engine.dart';
import '../../data/local/database.dart';
import '../../data/local/outbox_helper.dart';
import '../../domain/models/workspace_profile_header.dart';
import '../../domain/repositories/i_profile_repository.dart';
import 'auth_providers.dart';
import 'company_providers.dart';
import 'database_providers.dart';
import 'profile_session_state.dart';

class DriftProfileRepository implements IProfileRepository {
  final AppDatabase db;
  final SyncEngine syncEngine;

  DriftProfileRepository({required this.db, required this.syncEngine});

  @override
  Future<List<WorkspaceProfileHeader>> getAccessibleProfiles(
      String accountId) async {
    if (accountId.isEmpty) return [];

    // 1. Query shared_memberships joined with companies
    final query = db.select(db.companies).join([
      innerJoin(
        db.sharedMemberships,
        db.sharedMemberships.profileId.equalsExp(db.companies.id),
      ),
    ])
      ..where(db.sharedMemberships.accountId.equals(accountId) &
          db.companies.isDeleted.equals(false));

    final rows = await query.get();

    final result = <WorkspaceProfileHeader>[];
    for (final row in rows) {
      final company = row.readTable(db.companies);
      final membership = row.readTable(db.sharedMemberships);

      result.add(
        WorkspaceProfileHeader(
          id: company.id,
          name: company.name,
          legalName: company.legalName,
          type: ProfileType.fromString(company.mode),
          role: ProfileRole.fromString(membership.role),
          currencyCode: company.currencyCode,
          gstin: company.gstin,
          isActive: company.isActive,
          updatedAt: company.updatedAt,
        ),
      );
    }

    // 2. Also include companies owned directly by accountId if membership wasn't backfilled
    final existingIds = result.map((p) => p.id).toSet();
    final ownerQuery = db.select(db.companies)
      ..where((c) => c.ownerId.equals(accountId) & c.isDeleted.equals(false));
    final ownerRows = await ownerQuery.get();
    for (final company in ownerRows) {
      if (!existingIds.contains(company.id)) {
        result.add(
          WorkspaceProfileHeader(
            id: company.id,
            name: company.name,
            legalName: company.legalName,
            type: ProfileType.fromString(company.mode),
            role: ProfileRole.owner,
            currencyCode: company.currencyCode,
            gstin: company.gstin,
            isActive: company.isActive,
            updatedAt: company.updatedAt,
          ),
        );
      }
    }

    return result;
  }

  @override
  Future<WorkspaceProfileHeader> createProfile({
    required String name,
    required ProfileType type,
    String currencyCode = 'INR',
    String? legalName,
    String? gstin,
    String? customId,
    String? accountId,
  }) async {
    final profileId = customId ??
        'prf_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    final now = DateTime.now();
    final effectiveLegalName = legalName ?? name;

    if (accountId == null || accountId.isEmpty) {
      throw ArgumentError(
        'A valid authenticated user UUID is required to create a workspace profile.',
      );
    }
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!uuidRegex.hasMatch(accountId)) {
      throw ArgumentError(
        'A valid authenticated user UUID is required. Received: "$accountId"',
      );
    }
    final effectiveAccountId = accountId;
    final membershipId = const Uuid().v4();

    await db.transaction(() async {
      // 1. Insert company with pending syncStatus and verified ownerId
      await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion.insert(
              id: profileId,
              name: name,
              legalName: effectiveLegalName,
              ownerId: Value(effectiveAccountId),
              mode: Value(type.canonicalValue),
              currencyCode: Value(currencyCode),
              gstin: Value(gstin),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // 2. Insert membership using valid UUID
      await db.into(db.sharedMemberships).insertOnConflictUpdate(
            SharedMembershipsCompanion.insert(
              id: membershipId,
              profileId: profileId,
              accountId: effectiveAccountId,
              role: 'owner',
              joinedAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // 3. Enqueue company outbox mutation (MUST BE ENQUEUED BEFORE membership)
      await enqueueMutation(
        db: db,
        table: 'companies',
        recordId: profileId,
        type: 'UPSERT',
        fullRowMap: {
          'id': profileId,
          'name': name,
          'legal_name': effectiveLegalName,
          'legalName': effectiveLegalName,
          'owner_id': effectiveAccountId,
          'ownerId': effectiveAccountId,
          'mode': type.canonicalValue,
          'currency_code': currencyCode,
          'currencyCode': currencyCode,
          'gstin': gstin,
          'created_at': encodeTime(now),
          'createdAt': encodeTime(now),
          'updated_at': encodeTime(now),
          'updatedAt': encodeTime(now),
          'is_deleted': false,
          'isDeleted': false,
          'is_cloud_sync_enabled': true,
          'is_active': true,
          'revision': 0,
        },
      );

      // 4. Enqueue membership outbox mutation (AFTER company)
      await enqueueMutation(
        db: db,
        table: 'shared_memberships',
        recordId: membershipId,
        type: 'UPSERT',
        fullRowMap: {
          'id': membershipId,
          'profile_id': profileId,
          'account_id': effectiveAccountId,
          'role': 'owner',
          'joined_at': encodeTime(now),
          'updated_at': encodeTime(now),
        },
      );

      // 5. Seed defaults
      if (type == ProfileType.expense) {
        // Cash wallet
        final walletId = '${profileId}_wal_cash';
        await db.into(db.expenseWallets).insertOnConflictUpdate(
              ExpenseWalletsCompanion.insert(
                id: walletId,
                profileId: profileId,
                name: 'Cash in Hand',
                walletType: const Value('cash'),
                currencyCode: Value(currencyCode),
                colorHex: const Value('#006C4C'),
                iconName: const Value('payments'),
                createdAt: Value(now),
                updatedAt: Value(now),
                syncStatus: const Value(SyncRecordStatus.pending),
              ),
            );

        await enqueueMutation(
          db: db,
          table: 'exp_wallets',
          recordId: walletId,
          type: 'UPSERT',
          fullRowMap: {
            'id': walletId,
            'profile_id': profileId,
            'name': 'Cash in Hand',
            'wallet_type': 'cash',
            'currency_code': currencyCode,
            'starting_balance_in_cents': 0,
            'current_balance_in_cents': 0,
            'color_hex': '#006C4C',
            'icon_name': 'payments',
            'is_archived': false,
            'is_deleted': false,
            'revision': 0,
            'created_at': encodeTime(now),
            'updated_at': encodeTime(now),
          },
        );

        // Core Categories
        final defaultCats = [
          ('Groceries & Food', 'expense', '#D32F2F', 'restaurant'),
          ('Salary & Income', 'income', '#388E3C', 'payments'),
          ('Utilities & Bills', 'expense', '#F57C00', 'lightbulb'),
          ('Transportation', 'expense', '#1976D2', 'directions_car'),
        ];

        for (final cat in defaultCats) {
          final catId = '${profileId}_cat_${cat.$1.toLowerCase().replaceAll(RegExp(r'\W+'), '_')}';
          await db.into(db.expenseCategories).insertOnConflictUpdate(
                ExpenseCategoriesCompanion.insert(
                  id: catId,
                  profileId: profileId,
                  name: cat.$1,
                  categoryType: Value(cat.$2),
                  colorHex: Value(cat.$3),
                  iconName: Value(cat.$4),
                  isSystem: const Value(true),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                  syncStatus: const Value(SyncRecordStatus.pending),
                ),
              );

          await enqueueMutation(
            db: db,
            table: 'exp_categories',
            recordId: catId,
            type: 'UPSERT',
            fullRowMap: {
              'id': catId,
              'profile_id': profileId,
              'name': cat.$1,
              'category_type': cat.$2,
              'color_hex': cat.$3,
              'icon_name': cat.$4,
              'is_system': true,
              'is_deleted': false,
              'revision': 0,
              'created_at': encodeTime(now),
              'updated_at': encodeTime(now),
            },
          );
        }
      }
    });

    // 6. Trigger background sync after transaction commit
    syncEngine.triggerBackgroundSync(companyId: profileId);

    return WorkspaceProfileHeader(
      id: profileId,
      name: name,
      legalName: effectiveLegalName,
      type: type,
      role: ProfileRole.owner,
      currencyCode: currencyCode,
      gstin: gstin,
      updatedAt: now,
    );
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    final now = DateTime.now();
    await (db.update(db.companies)..where((t) => t.id.equals(profileId))).write(
      CompaniesCompanion(
        isDeleted: const Value(true),
        syncStatus: const Value(SyncRecordStatus.pending),
        updatedAt: Value(now),
      ),
    );
    await enqueueMutation(
      db: db,
      table: 'companies',
      recordId: profileId,
      type: 'UPSERT',
      fullRowMap: {
        'id': profileId,
        'is_deleted': true,
        'isDeleted': true,
        'updated_at': encodeTime(now),
        'updatedAt': encodeTime(now),
      },
    );
    syncEngine.triggerBackgroundSync(companyId: profileId);
  }
}

final profileRepositoryProvider = Provider<IProfileRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  return DriftProfileRepository(db: db, syncEngine: syncEngine);
});

class ProfileSessionController extends Notifier<ProfileSessionState> {
  @override
  ProfileSessionState build() {
    final authState = ref.watch(authControllerProvider);
    if (!authState.isAuthenticated || authState.userId == null || authState.userId!.isEmpty) {
      return const UnauthenticatedSessionState();
    }

    final userId = authState.userId!;
    Future.microtask(() => loadProfilesForUser(userId));
    return LoadingProfilesSessionState(userId);
  }

  Future<void> loadProfilesForUser(String userId, {bool isLogin = false}) async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final profiles = await repo.getAccessibleProfiles(userId);
      if (!ref.mounted) return;

      if (profiles.isEmpty) {
        state = OnboardingRequiredSessionState(userId);
      } else if (profiles.length == 1) {
        final single = profiles.first;
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs?.setString('last_active_profile_$userId', single.id);

        state = ActiveProfileReadySessionState(
          userId: userId,
          activeProfile: single,
          availableProfiles: profiles,
        );
        _syncActiveCompany(single);
      } else {
        // Multiple profiles available
        if (isLogin) {
          // On fresh login with multiple profiles: strictly present profile selector
          state = ProfileSelectionRequiredSessionState(
            userId: userId,
            profiles: profiles,
          );
        } else {
          final prefs = ref.read(sharedPreferencesProvider);
          final lastActiveId = prefs?.getString('last_active_profile_$userId');
          final matched = profiles.where((p) => p.id == lastActiveId).firstOrNull;

          if (matched != null) {
            state = ActiveProfileReadySessionState(
              userId: userId,
              activeProfile: matched,
              availableProfiles: profiles,
            );
            _syncActiveCompany(matched);
          } else {
            state = ProfileSelectionRequiredSessionState(
              userId: userId,
              profiles: profiles,
            );
          }
        }
      }
    } catch (e) {
      if (ref.mounted) {
        state = SessionErrorState(e.toString());
      }
    }
  }

  void showProfileSelector() {
    if (state is ActiveProfileReadySessionState) {
      final curr = state as ActiveProfileReadySessionState;
      state = ProfileSelectionRequiredSessionState(
        userId: curr.userId,
        profiles: curr.availableProfiles,
      );
    }
  }

  Future<void> switchProfile(WorkspaceProfileHeader profile) async {
    final userId = state is ActiveProfileReadySessionState
        ? (state as ActiveProfileReadySessionState).userId
        : (state is ProfileSelectionRequiredSessionState
            ? (state as ProfileSelectionRequiredSessionState).userId
            : null);

    if (userId == null || userId.isEmpty) {
      state = const SessionErrorState('Cannot switch profile while unauthenticated.');
      return;
    }

    try {
      final repo = ref.read(profileRepositoryProvider);
      // Verify membership against database rather than trusting in-memory state
      final freshProfiles = await repo.getAccessibleProfiles(userId);
      final isAuthorized = freshProfiles.any((p) => p.id == profile.id);
      if (!isAuthorized) {
        state = const SessionErrorState(
          'Access Revoked: Your access to this workspace has been removed.',
        );
        return;
      }

      final targetProfile = freshProfiles.firstWhere((p) => p.id == profile.id);
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs?.setString('last_active_profile_$userId', targetProfile.id);

      state = ActiveProfileReadySessionState(
        userId: userId,
        activeProfile: targetProfile,
        availableProfiles: freshProfiles,
      );
      _syncActiveCompany(targetProfile);
    } catch (e) {
      if (ref.mounted) {
        state = SessionErrorState(e.toString());
      }
    }
  }

  void _syncActiveCompany(WorkspaceProfileHeader profile) {
    try {
      ref.read(companyControllerProvider.notifier).selectCompany(profile.id);
    } catch (_) {
      // Ignored if company controller is disposing
    }
  }

  Future<void> retry() async {
    final authState = ref.read(authControllerProvider);
    final userId = authState.userId;
    if (userId == null || userId.isEmpty) {
      state = const UnauthenticatedSessionState();
      return;
    }
    state = LoadingProfilesSessionState(userId);
    await loadProfilesForUser(userId);
  }

  void logout() {
    state = const UnauthenticatedSessionState();
  }
}

final profileSessionProvider =
    NotifierProvider<ProfileSessionController, ProfileSessionState>(
  ProfileSessionController.new,
);
