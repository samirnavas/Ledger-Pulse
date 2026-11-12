import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/network/sync_codec.dart';
import '../../core/network/sync_engine.dart';
import '../../data/accounting/voucher_posting_engine.dart';
import '../../data/local/audit_service.dart';
import '../../data/local/database.dart';
import '../../data/local/outbox_helper.dart';
import '../../data/models/company_model.dart';
import '../../domain/models/workspace_profile_header.dart';
import '../../domain/repositories/i_profile_repository.dart';
import 'auth_providers.dart';
import 'company_providers.dart';
import 'database_providers.dart';
import 'profile_session_state.dart';

class DriftProfileRepository implements IProfileRepository {
  final AppDatabase db;
  final SyncEngine syncEngine;
  final SupabaseClient? supabaseClient;
  final VoucherPostingEngine? postingEngine;

  DriftProfileRepository({
    required this.db,
    required this.syncEngine,
    this.supabaseClient,
    this.postingEngine,
  });

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
  Future<List<WorkspaceProfileHeader>> syncAndLoadRemoteWorkspaces(
      String accountId) async {
    if (accountId.isEmpty) return [];

    final client = supabaseClient ?? _getSafeSupabaseClient();
    if (client == null) {
      return getAccessibleProfiles(accountId);
    }

    // Parallel fetch with timeout for maximum responsiveness
    Map<String, dynamic>? remoteProfile;
    List<Map<String, dynamic>> remoteMemberships = [];
    List<Map<String, dynamic>> remoteCompanies = [];

    await Future.wait([
      (() async {
        try {
          final res = await client
              .from('user_profiles')
              .select()
              .eq('id', accountId)
              .maybeSingle()
              .timeout(const Duration(seconds: 8));
          if (res != null) {
            remoteProfile = Map<String, dynamic>.from(res);
          }
        } catch (e) {
          if (_isNetworkException(e)) rethrow;
          debugPrint('DriftProfileRepository: Error fetching user_profiles: $e');
        }
      })(),
      (() async {
        try {
          final res = await client
              .from('shared_memberships')
              .select()
              .eq('account_id', accountId)
              .timeout(const Duration(seconds: 8));
          remoteMemberships = List<Map<String, dynamic>>.from(res);
        } catch (e) {
          if (_isNetworkException(e)) rethrow;
          debugPrint('DriftProfileRepository: Error fetching shared_memberships: $e');
        }
      })(),
      (() async {
        try {
          final res = await client
              .from('companies')
              .select()
              .eq('is_deleted', false)
              .timeout(const Duration(seconds: 8));
          remoteCompanies = List<Map<String, dynamic>>.from(res);
        } catch (e) {
          if (_isNetworkException(e)) rethrow;
          debugPrint('DriftProfileRepository: Error fetching companies: $e');
        }
      })(),
    ]);

    // 4. Batch upsert into local Drift database in a single transaction
    await db.transaction(() async {
      for (final comp in remoteCompanies) {
        final compId = comp['id'] as String;
        final compName = comp['name'] as String? ?? '';
        final legalName = comp['legal_name'] as String? ??
            comp['legalName'] as String? ??
            compName;
        final mode = comp['mode'] as String? ?? 'ledger';
        final currencyCode = comp['currency_code'] as String? ??
            comp['currencyCode'] as String? ??
            'INR';
        final gstin = comp['gstin'] as String?;
        final ownerId = comp['owner_id'] as String? ??
            comp['ownerId'] as String? ??
            accountId;
        final isActive = comp['is_active'] as bool? ??
            comp['isActive'] as bool? ??
            true;
        final isDeleted = comp['is_deleted'] as bool? ??
            comp['isDeleted'] as bool? ??
            false;
        final createdAtStr = comp['created_at'] ?? comp['createdAt'];
        final updatedAtStr = comp['updated_at'] ?? comp['updatedAt'];
        final createdAt =
            createdAtStr != null ? decodeTime(createdAtStr) : DateTime.now();
        final updatedAt =
            updatedAtStr != null ? decodeTime(updatedAtStr) : DateTime.now();

        // Enforce workspace type immutability: preserve local mode if company exists locally
        final existingComp = await (db.select(db.companies)..where((c) => c.id.equals(compId))).getSingleOrNull();
        if (existingComp != null && existingComp.syncStatus != SyncRecordStatus.synced) {
          // Never overwrite newer local pending company changes with stale remote data
          continue;
        }
        final effectiveMode = existingComp != null ? existingComp.mode : mode;

        await db.into(db.companies).insertOnConflictUpdate(
              CompaniesCompanion.insert(
                id: compId,
                name: compName,
                legalName: legalName,
                mode: Value(effectiveMode),
                currencyCode: Value(currencyCode),
                gstin: Value(gstin),
                ownerId: Value(ownerId),
                isActive: Value(isActive),
                isDeleted: Value(isDeleted),
                createdAt: Value(createdAt),
                updatedAt: Value(updatedAt),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
      }

      for (final mem in remoteMemberships) {
        final memId = mem['id'].toString();
        final profId = mem['profile_id']?.toString() ??
            mem['profileId']?.toString() ??
            '';
        final accId = mem['account_id']?.toString() ??
            mem['accountId']?.toString() ??
            accountId;
        final role = mem['role'] as String? ?? 'owner';
        final joinedAtStr = mem['joined_at'] ?? mem['joinedAt'];
        final updatedAtStr = mem['updated_at'] ?? mem['updatedAt'];
        final joinedAt =
            joinedAtStr != null ? decodeTime(joinedAtStr) : DateTime.now();
        final updatedAt =
            updatedAtStr != null ? decodeTime(updatedAtStr) : DateTime.now();

        if (profId.isNotEmpty) {
          await db.into(db.sharedMemberships).insertOnConflictUpdate(
                SharedMembershipsCompanion.insert(
                  id: memId,
                  profileId: profId,
                  accountId: accId,
                  role: role,
                  joinedAt: Value(joinedAt),
                  updatedAt: Value(updatedAt),
                ),
              );
        }
      }

      final profData = remoteProfile;
      if (profData != null) {
        final profId = profData['id'] as String;
        final existingProf = await (db.select(db.userProfiles)..where((u) => u.id.equals(profId))).getSingleOrNull();
        if (existingProf == null || existingProf.syncStatus == SyncRecordStatus.synced) {
          final profName = profData['name'] as String? ?? '';
          final phone = profData['phone_number'] as String? ??
              profData['phoneNumber'] as String? ??
              '';
          final email = profData['email'] as String? ?? '';
          final activeCompanyId = profData['active_company_id'] as String? ??
              profData['activeCompanyId'] as String? ??
              '';
          final role = profData['role'] as String? ?? 'admin';
          final createdAtStr =
              profData['created_at'] ?? profData['createdAt'];
          final updatedAtStr =
              profData['updated_at'] ?? profData['updatedAt'];
          final createdAt =
              createdAtStr != null ? decodeTime(createdAtStr) : DateTime.now();
          final updatedAt =
              updatedAtStr != null ? decodeTime(updatedAtStr) : DateTime.now();

          await db.into(db.userProfiles).insertOnConflictUpdate(
                UserProfilesCompanion.insert(
                  id: profId,
                  name: profName,
                  phoneNumber: phone,
                  email: email,
                  businessName: Value(profData['business_name'] as String? ??
                      profData['businessName'] as String?),
                  address: Value(profData['address'] as String?),
                  gstin: Value(profData['gstin'] as String?),
                  businessType: Value(profData['business_type'] as String? ??
                      profData['businessType'] as String?),
                  bankName: Value(profData['bank_name'] as String? ??
                      profData['bankName'] as String?),
                  bankAccountNumber: Value(profData['bank_account_number'] as String? ??
                      profData['bankAccountNumber'] as String?),
                  bankIfsc: Value(profData['bank_ifsc'] as String? ??
                      profData['bankIfsc'] as String?),
                  upiId: Value(profData['upi_id'] as String? ??
                      profData['upiId'] as String?),
                  activeCompanyId: Value(activeCompanyId),
                  role: Value(role),
                  createdAt: Value(createdAt),
                  updatedAt: Value(updatedAt),
                  syncStatus: const Value(SyncRecordStatus.synced),
                ),
              );
        }
      }
    });

    return getAccessibleProfiles(accountId);
  }

  static SupabaseClient? _getSafeSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static bool _isNetworkException(Object e) {
    if (e is TimeoutException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('handshakeexception') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('failed host lookup') ||
        s.contains('network error') ||
        s.contains('network is unreachable') ||
        s.contains('timed out') ||
        s.contains('timeout');
  }

  @override
  Future<WorkspaceProfileHeader> createProfile({
    required String name,
    required ProfileType type,
    String currencyCode = 'INR',
    String? legalName,
    String? gstin,
    String? stateCode,
    String? dealerType,
    Set<AppModule>? enabledModules,
    Map<String, int>? initialWalletBalancesInCents,
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

    // Check for existing membership to ensure idempotency on repeated calls
    final existingMembership = await (db.select(db.sharedMemberships)
          ..where((m) =>
              m.profileId.equals(profileId) &
              m.accountId.equals(effectiveAccountId)))
        .getSingleOrNull();
    final membershipId = existingMembership?.id ?? const Uuid().v4();

    final effectiveModules = enabledModules ??
        ModuleCatalog.defaultsFor(
          type == ProfileType.expense
              ? CompanyMode.expenseTracker
              : CompanyMode.ledger,
        );

    final effectiveDealerType = dealerType ?? (type == ProfileType.expense ? '' : 'regular');

    final companyModel = Company(
      id: profileId,
      name: name,
      legalName: effectiveLegalName,
      currencyCode: currencyCode,
      mode: type == ProfileType.expense ? CompanyMode.expenseTracker : CompanyMode.ledger,
      enabledModules: effectiveModules,
      gstin: gstin,
      stateCode: stateCode,
      dealerType: effectiveDealerType,
      ownerId: effectiveAccountId,
      createdAt: now,
      updatedAt: now,
    );

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
              stateCode: Value(stateCode),
              dealerType: Value(effectiveDealerType),
              enabledModulesJson: Value(
                jsonEncode(effectiveModules.map((m) => m.name).toList()),
              ),
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
          'state_code': stateCode,
          'stateCode': stateCode,
          'dealer_type': effectiveDealerType,
          'dealerType': effectiveDealerType,
          'enabled_modules': effectiveModules.map((m) => m.name).toList(),
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

      // 5. Seed chart of accounts for company
      final engine = postingEngine ?? VoucherPostingEngine(db, AuditService(db));
      await engine.seedAccountsFor(
        companyModel,
        initialWalletBalancesInCents: initialWalletBalancesInCents,
      );

      // 6. Seed defaults for expense mode
      if (type == ProfileType.expense) {
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

        final defaultCats = [
          ('Groceries & Food', 'expense', '#D32F2F', 'restaurant'),
          ('Salary & Income', 'income', '#388E3C', 'payments'),
          ('Utilities & Bills', 'expense', '#F57C00', 'lightbulb'),
          ('Transportation', 'expense', '#1976D2', 'directions_car'),
        ];

        for (final cat in defaultCats) {
          final catId =
              '${profileId}_cat_${cat.$1.toLowerCase().replaceAll(RegExp(r'\W+'), '_')}';
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

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});

final profileRepositoryProvider = Provider<IProfileRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final client = ref.watch(supabaseClientProvider);
  return DriftProfileRepository(
    db: db,
    syncEngine: syncEngine,
    supabaseClient: client,
    postingEngine: VoucherPostingEngine(db, AuditService(db)),
  );
});

class ProfileSessionController extends Notifier<ProfileSessionState> {
  Completer<void>? _loadingCompleter;
  String? _currentlyLoadingUserId;
  String? _currentActiveUserId;
  WorkspaceProfileHeader? _currentActiveProfile;
  List<WorkspaceProfileHeader>? _currentAvailableProfiles;
  bool _currentIsOffline = false;

  @override
  ProfileSessionState build() {
    final authState = ref.watch(authControllerProvider);
    if (!authState.isAuthenticated ||
        authState.userId == null ||
        authState.userId!.isEmpty) {
      _currentActiveUserId = null;
      _currentActiveProfile = null;
      _currentAvailableProfiles = null;
      _currentIsOffline = false;
      return const GuestReadySessionState();
    }

    final userId = authState.userId!;

    // Token refresh or non-identity auth change guard:
    // If active profile is already established for this exact user, preserve it
    if (_currentActiveUserId == userId && _currentActiveProfile != null) {
      return _currentIsOffline
          ? OfflineActiveProfileReadySessionState(
              userId: userId,
              activeProfile: _currentActiveProfile!,
              availableProfiles:
                  _currentAvailableProfiles ?? [_currentActiveProfile!],
            )
          : ActiveProfileReadySessionState(
              userId: userId,
              activeProfile: _currentActiveProfile!,
              availableProfiles:
                  _currentAvailableProfiles ?? [_currentActiveProfile!],
              isOffline: false,
            );
    }

    Future.microtask(() => loadProfilesForUser(userId));
    return LoadingProfilesSessionState(userId);
  }

  Future<void> loadProfilesForUser(String userId, {bool isLogin = false}) async {
    // 1. Guard against concurrent duplicate calls for the same user
    if (_currentlyLoadingUserId == userId && _loadingCompleter != null) {
      await _loadingCompleter!.future;
      if (isLogin && state is ActiveProfileReadySessionState) {
        final ready = state as ActiveProfileReadySessionState;
        if (ready.availableProfiles.length > 1) {
          _currentActiveProfile = null;
          state = ProfileSelectionRequiredSessionState(
            userId: userId,
            profiles: ready.availableProfiles,
          );
        }
      }
      return;
    }

    _currentlyLoadingUserId = userId;
    final completer = Completer<void>();
    _loadingCompleter = completer;

    try {
      // 2. Validate activeUserIdProvider matches to guard against account-switch race conditions
      final currentActiveId = ref.read(activeUserIdProvider);
      if (currentActiveId != userId) {
        return;
      }

      // 3. Inspect local Drift cache first
      final repo = ref.read(profileRepositoryProvider);
      List<WorkspaceProfileHeader> localProfiles = [];
      try {
        localProfiles = await repo.getAccessibleProfiles(userId);
      } catch (e) {
        debugPrint('ProfileSessionController: Error reading local cache: $e');
      }

      // FAST PATH: On app reopen / restart (!isLogin), if local workspaces already exist,
      // activate the workspace immediately from SQLite cache.
      // This eliminates the 10-15s "Loading your workspaces..." screen and opens HomeShell instantly.
      if (!isLogin && localProfiles.isNotEmpty) {
        await _resolveActiveWorkspace(
          userId: userId,
          profiles: localProfiles,
          isOffline: false,
          isLogin: false,
        );

        // Perform background remote synchronization
        try {
          final freshProfiles = await repo.syncAndLoadRemoteWorkspaces(userId);
          if (ref.mounted && ref.read(activeUserIdProvider) == userId) {
            _currentAvailableProfiles = freshProfiles;
            if (state is ActiveProfileReadySessionState) {
              final ready = state as ActiveProfileReadySessionState;
              final stillExists =
                  freshProfiles.any((p) => p.id == ready.activeProfile.id);
              if (stillExists) {
                final updated = freshProfiles
                    .firstWhere((p) => p.id == ready.activeProfile.id);
                _currentActiveProfile = updated;
                state = ActiveProfileReadySessionState(
                  userId: userId,
                  activeProfile: updated,
                  availableProfiles: freshProfiles,
                  isOffline: false,
                );
              } else if (freshProfiles.isNotEmpty) {
                if (freshProfiles.length == 1) {
                  await switchProfile(freshProfiles.first);
                } else {
                  state = ProfileSelectionRequiredSessionState(
                    userId: userId,
                    profiles: freshProfiles,
                  );
                }
              }
            }
          }
        } catch (e) {
          debugPrint('ProfileSessionController: Background workspace sync note: $e');
          if (DriftProfileRepository._isNetworkException(e)) {
            if (ref.mounted && state is ActiveProfileReadySessionState) {
              final ready = state as ActiveProfileReadySessionState;
              state = OfflineActiveProfileReadySessionState(
                userId: userId,
                activeProfile: ready.activeProfile,
                availableProfiles: ready.availableProfiles,
              );
            }
          }
        }
        return;
      }

      // 4. Attempt remote synchronization if online
      bool remoteSuccess = false;
      bool isNetworkError = false;
      String? remoteError;
      List<WorkspaceProfileHeader> freshProfiles = localProfiles;

      try {
        freshProfiles = await repo.syncAndLoadRemoteWorkspaces(userId);
        remoteSuccess = true;
      } catch (e) {
        debugPrint('ProfileSessionController: Remote workspace load failed: $e');
        isNetworkError = DriftProfileRepository._isNetworkException(e);
        remoteError = e.toString();
        if (e is AuthException) {
          final msg = e.message.toLowerCase();
          if (msg.contains('expired') ||
              msg.contains('invalid jwt') ||
              msg.contains('not found')) {
            if (ref.mounted) {
              state = AuthExpiredSessionState(e.message);
            }
            return;
          }
        }
      }

      if (!ref.mounted) return;
      // Guard against user changed during asynchronous network/disk operations
      if (ref.read(activeUserIdProvider) != userId) {
        return;
      }

      // 5. Offline fallback with cached workspace
      if (!remoteSuccess && localProfiles.isNotEmpty) {
        await _resolveActiveWorkspace(
          userId: userId,
          profiles: localProfiles,
          isOffline: true,
          isLogin: isLogin,
        );
        return;
      }

      // 6. Network failure with no local cache
      if (!remoteSuccess && localProfiles.isEmpty) {
        if (isNetworkError) {
          state = const SessionErrorState(
            'Network connection unavailable. Please check your internet connection to load your workspaces.',
            isNetworkError: true,
          );
        } else {
          state = SessionErrorState(
            remoteError ?? 'Failed to load workspace profiles.',
            isNetworkError: false,
          );
        }
        return;
      }

      // 7. Successful load: resolve active workspace
      await _resolveActiveWorkspace(
        userId: userId,
        profiles: freshProfiles,
        isOffline: false,
        isLogin: isLogin,
      );
    } catch (e) {
      if (ref.mounted) {
        state = SessionErrorState(e.toString());
      }
    } finally {
      if (_currentlyLoadingUserId == userId) {
        _currentlyLoadingUserId = null;
        _loadingCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> _resolveActiveWorkspace({
    required String userId,
    required List<WorkspaceProfileHeader> profiles,
    required bool isOffline,
    required bool isLogin,
  }) async {
    if (profiles.isEmpty) {
      state = NoAccessibleWorkspaceSessionState(userId);
      return;
    }

    final prefs = ref.read(sharedPreferencesProvider);
    var lastActiveId = prefs?.getString('last_active_profile_$userId') ??
        prefs?.getString('last_active_company_id_$userId');

    if (lastActiveId == null || lastActiveId.isEmpty) {
      try {
        final db = ref.read(appDatabaseProvider);
        final profRow = await (db.select(db.userProfiles)
              ..where((t) => t.id.equals(userId) & t.isDeleted.equals(false)))
            .getSingleOrNull();
        if (profRow != null &&
            profRow.activeCompanyId.isNotEmpty &&
            profRow.activeCompanyId != 'cmp_default') {
          lastActiveId = profRow.activeCompanyId;
        }
      } catch (_) {}
    }

    if (profiles.length == 1) {
      final single = profiles.first;
      await prefs?.setString('last_active_profile_$userId', single.id);
      await prefs?.setString('last_active_company_id_$userId', single.id);
      await prefs?.setString('last_active_company_id', single.id);

      _currentActiveUserId = userId;
      _currentActiveProfile = single;
      _currentAvailableProfiles = profiles;
      _currentIsOffline = isOffline;

      state = isOffline
          ? OfflineActiveProfileReadySessionState(
              userId: userId,
              activeProfile: single,
              availableProfiles: profiles,
            )
          : ActiveProfileReadySessionState(
              userId: userId,
              activeProfile: single,
              availableProfiles: profiles,
              isOffline: false,
            );

      _syncActiveCompany(single);
      if (!isOffline) {
        try {
          ref
              .read(syncEngineProvider)
              .triggerBackgroundSync(companyId: single.id);
        } catch (_) {}
      }
      return;
    }

    // Multiple profiles available
    if (isLogin) {
      _currentActiveUserId = userId;
      _currentActiveProfile = null;
      _currentAvailableProfiles = profiles;
      // On fresh explicit login with multiple profiles: present profile selector
      state = ProfileSelectionRequiredSessionState(
        userId: userId,
        profiles: profiles,
      );
      return;
    }

    // App restart / session restoration: attempt to restore previously selected workspace
    final matched = profiles.where((p) => p.id == lastActiveId).firstOrNull;
    if (matched != null) {
      _currentActiveUserId = userId;
      _currentActiveProfile = matched;
      _currentAvailableProfiles = profiles;
      _currentIsOffline = isOffline;

      state = isOffline
          ? OfflineActiveProfileReadySessionState(
              userId: userId,
              activeProfile: matched,
              availableProfiles: profiles,
            )
          : ActiveProfileReadySessionState(
              userId: userId,
              activeProfile: matched,
              availableProfiles: profiles,
              isOffline: false,
            );

      _syncActiveCompany(matched);
      if (!isOffline) {
        try {
          ref
              .read(syncEngineProvider)
              .triggerBackgroundSync(companyId: matched.id);
        } catch (_) {}
      }
    } else {
      // Previously selected workspace no longer accessible or not set:
      // Fall back safely to profile selector
      state = ProfileSelectionRequiredSessionState(
        userId: userId,
        profiles: profiles,
      );
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
      state = const SessionErrorState(
          'Cannot switch profile while unauthenticated.');
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
      await prefs?.setString(
          'last_active_company_id_$userId', targetProfile.id);
      await prefs?.setString('last_active_company_id', targetProfile.id);

      // Persist activeCompanyId to local db.userProfiles with pending status and enqueue outbox
      try {
        final db = ref.read(appDatabaseProvider);
        final now = DateTime.now();
        await (db.update(db.userProfiles)..where((t) => t.id.equals(userId))).write(
          UserProfilesCompanion(
            activeCompanyId: Value(targetProfile.id),
            updatedAt: Value(now),
            syncStatus: const Value(SyncRecordStatus.pending),
          ),
        );
        await enqueueMutation(
          db: db,
          table: 'user_profiles',
          recordId: userId,
          type: 'UPSERT',
          fullRowMap: {
            'id': userId,
            'activeCompanyId': targetProfile.id,
            'updatedAt': now,
          },
        );
      } catch (e) {
        debugPrint('ProfileSessionController: Error updating active profile: $e');
      }

      final isOffline = state is ActiveProfileReadySessionState &&
          (state as ActiveProfileReadySessionState).isOffline;

      _currentActiveUserId = userId;
      _currentActiveProfile = targetProfile;
      _currentAvailableProfiles = freshProfiles;
      _currentIsOffline = isOffline;

      state = isOffline
          ? OfflineActiveProfileReadySessionState(
              userId: userId,
              activeProfile: targetProfile,
              availableProfiles: freshProfiles,
            )
          : ActiveProfileReadySessionState(
              userId: userId,
              activeProfile: targetProfile,
              availableProfiles: freshProfiles,
              isOffline: false,
            );

      _syncActiveCompany(targetProfile);
      if (!isOffline) {
        try {
          ref
              .read(syncEngineProvider)
              .triggerBackgroundSync(companyId: targetProfile.id);
        } catch (_) {}
      }
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
      state = const GuestReadySessionState();
      return;
    }
    state = LoadingProfilesSessionState(userId);
    await loadProfilesForUser(userId);
  }

  void logout() {
    _currentActiveUserId = null;
    _currentActiveProfile = null;
    _currentAvailableProfiles = null;
    _currentIsOffline = false;
    state = const GuestReadySessionState();
  }
}

final profileSessionProvider =
    NotifierProvider<ProfileSessionController, ProfileSessionState>(
  ProfileSessionController.new,
);
