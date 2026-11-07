import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/sync_engine.dart';
import '../../data/local/database.dart';
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
    // 1. Query shared_memberships joined with companies
    final query = db.select(db.companies).join([
      innerJoin(
        db.sharedMemberships,
        db.sharedMemberships.profileId.equalsExp(db.companies.id),
      ),
    ])
      ..where((db.sharedMemberships.accountId.equals(accountId) |
              db.sharedMemberships.accountId.equals('usr_default')) &
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
    final effectiveAccountId = (accountId != null && accountId.isNotEmpty)
        ? accountId
        : 'usr_default';

    await db.transaction(() async {
      // 1. Insert company
      await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion.insert(
              id: profileId,
              name: name,
              legalName: effectiveLegalName,
              mode: Value(type == ProfileType.expense ? 'expense' : 'ledger'),
              currencyCode: Value(currencyCode),
              gstin: Value(gstin),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
            ),
          );

      // 2. Insert membership
      await db.into(db.sharedMemberships).insertOnConflictUpdate(
            SharedMembershipsCompanion.insert(
              id: 'mem_${DateTime.now().millisecondsSinceEpoch}',
              profileId: profileId,
              accountId: effectiveAccountId,
              role: 'owner',
              joinedAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // 3. Seed defaults
      if (type == ProfileType.expense) {
        // Cash wallet
        await db.into(db.expenseWallets).insertOnConflictUpdate(
              ExpenseWalletsCompanion.insert(
                id: '${profileId}_wal_cash',
                profileId: profileId,
                name: 'Cash in Hand',
                walletType: const Value('cash'),
                currencyCode: Value(currencyCode),
                colorHex: const Value('#006C4C'),
                iconName: const Value('payments'),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );

        // Core Categories
        final defaultCats = [
          ('Groceries & Food', 'expense', '#D32F2F', 'restaurant'),
          ('Salary & Income', 'income', '#388E3C', 'payments'),
          ('Utilities & Bills', 'expense', '#F57C00', 'lightbulb'),
          ('Transportation', 'expense', '#1976D2', 'directions_car'),
        ];

        for (final cat in defaultCats) {
          await db.into(db.expenseCategories).insertOnConflictUpdate(
                ExpenseCategoriesCompanion.insert(
                  id: '${profileId}_cat_${cat.$1.toLowerCase().replaceAll(RegExp(r'\W+'), '_')}',
                  profileId: profileId,
                  name: cat.$1,
                  categoryType: Value(cat.$2),
                  colorHex: Value(cat.$3),
                  iconName: Value(cat.$4),
                  isSystem: const Value(true),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
        }
      }
    });

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
    await (db.update(db.companies)..where((t) => t.id.equals(profileId))).write(
      CompaniesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
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
    if (!authState.isAuthenticated) {
      return const UnauthenticatedSessionState();
    }

    final userId = authState.phoneNumber ?? 'usr_default';
    Future.microtask(() => loadProfilesForUser(userId));
    return LoadingProfilesSessionState(userId);
  }

  Future<void> loadProfilesForUser(String userId) async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final profiles = await repo.getAccessibleProfiles(userId);

      if (profiles.isEmpty) {
        state = OnboardingRequiredSessionState(userId);
      } else if (profiles.length == 1) {
        state = ActiveProfileReadySessionState(
          userId: userId,
          activeProfile: profiles.first,
          availableProfiles: profiles,
        );
        _syncActiveCompany(profiles.first);
      } else {
        // Multiple profiles available
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
          // If no active profile saved or previous one revoked, show profile selector
          state = ProfileSelectionRequiredSessionState(
            userId: userId,
            profiles: profiles,
          );
        }
      }
    } catch (e) {
      state = SessionErrorState(e.toString());
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

  void switchProfile(WorkspaceProfileHeader profile) {
    if (state is ActiveProfileReadySessionState ||
        state is ProfileSelectionRequiredSessionState) {
      final userId = state is ActiveProfileReadySessionState
          ? (state as ActiveProfileReadySessionState).userId
          : (state as ProfileSelectionRequiredSessionState).userId;
      final available = state is ActiveProfileReadySessionState
          ? (state as ActiveProfileReadySessionState).availableProfiles
          : (state as ProfileSelectionRequiredSessionState).profiles;

      // Ensure membership is not revoked
      final isAuthorized = available.any((p) => p.id == profile.id);
      if (!isAuthorized) {
        state = const SessionErrorState(
          'Access Revoked: Your access to this workspace has been removed.',
        );
        return;
      }

      final prefs = ref.read(sharedPreferencesProvider);
      prefs?.setString('last_active_profile_$userId', profile.id);

      state = ActiveProfileReadySessionState(
        userId: userId,
        activeProfile: profile,
        availableProfiles: available,
      );
      _syncActiveCompany(profile);
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
    final userId = authState.phoneNumber ?? 'usr_default';
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

