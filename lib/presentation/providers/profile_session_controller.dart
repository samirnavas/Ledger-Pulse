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
import 'database_providers.dart';
import 'profile_provider.dart';
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

    // 1. Query shared_memberships joined with canonical profiles
    final profileQuery = db.select(db.profiles).join([
      innerJoin(
        db.sharedMemberships,
        db.sharedMemberships.profileId.equalsExp(db.profiles.id),
      ),
      leftOuterJoin(
        db.companies,
        db.companies.profileId.equalsExp(db.profiles.id) |
            db.companies.id.equalsExp(db.profiles.id),
      ),
    ])
      ..where(db.sharedMemberships.accountId.equals(accountId) &
          db.profiles.isDeleted.equals(false));

    final profileRows = await profileQuery.get();
    final result = <WorkspaceProfileHeader>[];

    for (final row in profileRows) {
      final prof = row.readTable(db.profiles);
      final membership = row.readTable(db.sharedMemberships);
      final comp = row.readTableOrNull(db.companies);

      result.add(
        WorkspaceProfileHeader(
          id: prof.id,
          name: prof.name,
          legalName: comp?.legalName ?? prof.name,
          type: ProfileType.fromString(prof.profileType),
          role: ProfileRole.fromString(membership.role),
          currencyCode: prof.currencyCode,
          gstin: comp?.gstin,
          isActive: prof.isActive,
          updatedAt: prof.updatedAt,
        ),
      );
    }

    // 2. Also include profiles owned directly by accountId if membership wasn't backfilled
    final existingIds = result.map((p) => p.id).toSet();
    final ownerProfiles = await (db.select(db.profiles)
          ..where((p) => p.ownerId.equals(accountId) & p.isDeleted.equals(false)))
        .get();
    for (final prof in ownerProfiles) {
      if (!existingIds.contains(prof.id)) {
        final comp = await (db.select(db.companies)
              ..where((c) =>
                  (c.profileId.equals(prof.id) | c.id.equals(prof.id)) &
                  c.isDeleted.equals(false)))
            .getSingleOrNull();
        result.add(
          WorkspaceProfileHeader(
            id: prof.id,
            name: prof.name,
            legalName: comp?.legalName ?? prof.name,
            type: ProfileType.fromString(prof.profileType),
            role: ProfileRole.owner,
            currencyCode: prof.currencyCode,
            gstin: comp?.gstin,
            isActive: prof.isActive,
            updatedAt: prof.updatedAt,
          ),
        );
        existingIds.add(prof.id);
      }
    }

    // 3. Fallback: If no profiles table rows found, fallback to legacy companies
    if (result.isEmpty) {
      final query = db.select(db.companies).join([
        innerJoin(
          db.sharedMemberships,
          db.sharedMemberships.profileId.equalsExp(db.companies.id),
        ),
      ])
        ..where(db.sharedMemberships.accountId.equals(accountId) &
            db.companies.isDeleted.equals(false));

      final rows = await query.get();
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

    final authUser = client.auth.currentUser;
    if (authUser?.id != accountId || db.userId != accountId) {
      throw StateError('Workspace database belongs to a different account.');
    }

    final results = await Future.wait([
      client
          .from('workspaces')
          .select()
          .eq('owner_user_id', accountId)
          .timeout(const Duration(seconds: 8)),
      client
          .from('users')
          .select()
          .eq('id', accountId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8)),
    ]);
    final workspaces = results[0] as List<Map<String, dynamic>>;
    final personal = results[1] as Map<String, dynamic>?;
    final visibleIds = <String>{};

    await db.transaction(() async {
      for (final workspace in workspaces) {
        if (workspace['owner_user_id'] != accountId) {
          throw const FormatException('Foreign workspace in account response.');
        }
        final id = workspace['id'] as String;
        final lifecycle = workspace['lifecycle_state'] as String;
        final existing = await (db.select(db.profiles)
              ..where((row) => row.id.equals(id)))
            .getSingleOrNull();
        if (existing != null && existing.ownerId != accountId) {
          throw StateError('Workspace belongs to a different local account.');
        }
        if (lifecycle != 'deleted') visibleIds.add(id);
        await db.into(db.profiles).insertOnConflictUpdate(
              ProfilesCompanion.insert(
                id: id,
                name: workspace['name'] as String,
                profileType: Value(workspace['workspace_type'] as String),
                currencyCode: Value(workspace['currency_code'] as String),
                ownerId: Value(accountId),
                isActive: Value(lifecycle == 'active'),
                isDeleted: Value(lifecycle == 'deleted'),
                createdAt: Value(decodeTime(workspace['created_at'])),
                updatedAt: Value(decodeTime(workspace['updated_at'])),
                revision: Value((workspace['revision'] as num).toInt()),
                syncStatus: const Value(SyncRecordStatus.synced),
              ),
            );
      }
      if (personal != null) {
        if (personal['id'] != accountId) {
          throw const FormatException('Foreign user in account response.');
        }
        final existing = await (db.select(db.userProfiles)
              ..where((row) => row.id.equals(accountId)))
            .getSingleOrNull();
        if (existing == null || existing.syncStatus == SyncRecordStatus.synced) {
          await db.into(db.userProfiles).insertOnConflictUpdate(
                UserProfilesCompanion.insert(
                  id: accountId,
                  name: personal['display_name'] as String,
                  phoneNumber: authUser?.phone ?? '',
                  email: authUser?.email ?? '',
                  createdAt: Value(decodeTime(personal['created_at'])),
                  updatedAt: Value(decodeTime(personal['updated_at'])),
                  syncStatus: const Value(SyncRecordStatus.synced),
                ),
              );
        }
      }
      if (client.auth.currentUser?.id != accountId) {
        throw StateError('Account changed while loading workspaces.');
      }
    });

    final local = await getAccessibleProfiles(accountId);
    final accessible = <WorkspaceProfileHeader>[];
    for (final workspace in local) {
      if (visibleIds.contains(workspace.id)) {
        accessible.add(workspace);
        continue;
      }
      if (!workspace.isExpense || workspace.role != ProfileRole.owner) continue;
      final pending = await (db.select(db.profiles)..where((row) =>
          row.id.equals(workspace.id) & row.ownerId.equals(accountId) &
          row.revision.equals(0) & row.syncStatus.equalsValue(SyncRecordStatus.pending)))
          .getSingleOrNull();
      if (pending == null) continue;
      final localCreate = await (db.select(db.syncOutbox)..where((row) =>
          row.targetTable.equals('profiles') & row.recordId.equals(workspace.id)))
          .getSingleOrNull();
      if (localCreate != null ||
          (await syncEngine.workspaceSync?.hasPendingCreation(workspace.id) ?? false)) {
        accessible.add(workspace);
      }
    }
    if (client.auth.currentUser?.id != accountId) {
      throw StateError('Account changed while loading workspaces.');
    }
    return accessible;
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
    String? address,
    String? bankName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? upiId,
    String? stateCode,
    String? dealerType,
    Set<AppModule>? enabledModules,
    Map<String, int>? initialWalletBalancesInCents,
    String? customId,
    String? accountId,
  }) async {
    final profileId = customId ?? const Uuid().v4();
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
      address: address,
      bankName: bankName,
      bankAccountNumber: bankAccountNumber,
      bankIfsc: bankIfsc,
      upiId: upiId,
      stateCode: stateCode,
      dealerType: effectiveDealerType,
      ownerId: effectiveAccountId,
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction(() async {
      // 1. Insert canonical profile with pending syncStatus and verified ownerId
      await db.into(db.profiles).insertOnConflictUpdate(
            ProfilesCompanion.insert(
              id: profileId,
              name: name,
              profileType: Value(type.canonicalValue),
              currencyCode: Value(currencyCode),
              ownerId: Value(effectiveAccountId),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              revision: const Value(0),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // 2. Enqueue canonical profile mutation (MUST BE ENQUEUED FIRST)
      await enqueueMutation(
        db: db,
        table: 'profiles',
        recordId: profileId,
        type: 'UPSERT',
        fullRowMap: {
          'id': profileId,
          'name': name,
          'mode': type.canonicalValue,
          'profile_type': type.canonicalValue,
          'currency_code': currencyCode,
          'owner_id': effectiveAccountId,
          'created_at': encodeTime(now),
          'updated_at': encodeTime(now),
          'is_deleted': false,
          'revision': 0,
        },
      );

      // 3. Insert company row linking to canonical profile_id
      await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion.insert(
              id: profileId,
              profileId: Value(profileId),
              name: name,
              legalName: effectiveLegalName,
              ownerId: Value(effectiveAccountId),
              mode: Value(type.canonicalValue),
              currencyCode: Value(currencyCode),
              gstin: Value(gstin),
              address: Value(address),
              bankName: Value(bankName),
              bankAccountNumber: Value(bankAccountNumber),
              bankIfsc: Value(bankIfsc),
              upiId: Value(upiId),
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

      // 4. Enqueue company mutation (BEFORE shared_memberships)
      await enqueueMutation(
        db: db,
        table: 'companies',
        recordId: profileId,
        type: 'UPSERT',
        fullRowMap: {
          'id': profileId,
          'profile_id': profileId,
          'name': name,
          'legal_name': effectiveLegalName,
          'legalName': effectiveLegalName,
          'owner_id': effectiveAccountId,
          'ownerId': effectiveAccountId,
          'mode': type.canonicalValue,
          'currency_code': currencyCode,
          'currencyCode': currencyCode,
          'gstin': gstin,
          'address': address,
          'bank_name': bankName,
          'bank_account_number': bankAccountNumber,
          'bank_ifsc': bankIfsc,
          'upi_id': upiId,
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

      // 5. Insert membership using valid UUID
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

      // 6. Enqueue membership outbox mutation (AFTER company)
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

      // 7. Seed accounts for Ledger mode
      if (type == ProfileType.ledger) {
        final engine = postingEngine ?? VoucherPostingEngine(db, AuditService(db));
        await engine.seedAccountsFor(
          companyModel,
          initialWalletBalancesInCents: initialWalletBalancesInCents,
        );
      }

      // 8. Seed defaults for expense mode (zero accounting vouchers or accounts)
      if (type == ProfileType.expense) {
        final initialCash = initialWalletBalancesInCents?['cash'] ??
            initialWalletBalancesInCents?['Cash in Hand'] ??
            0;
        final legacyWalletId = '${profileId}_wal_cash';
        final legacyWallet = await (db.select(db.expenseWallets)
              ..where((row) =>
                  row.id.equals(legacyWalletId) & row.profileId.equals(profileId)))
            .getSingleOrNull();
        final walletId = legacyWallet?.id ??
            const Uuid().v5(Namespace.url.value, 'ledgerpulse:$profileId:wallet:cash');
        await db.into(db.expenseWallets).insertOnConflictUpdate(
              ExpenseWalletsCompanion.insert(
                id: walletId,
                profileId: profileId,
                name: 'Cash in Hand',
                walletType: const Value('cash'),
                currencyCode: Value(currencyCode),
                startingBalanceInCents: Value(initialCash),
                currentBalanceInCents: Value(initialCash),
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
            'starting_balance_in_cents': initialCash,
            'current_balance_in_cents': initialCash,
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
          final categoryKey = cat.$1.toLowerCase().replaceAll(RegExp(r'\W+'), '_');
          final legacyCategoryId = '${profileId}_cat_$categoryKey';
          final legacyCategory = await (db.select(db.expenseCategories)
                ..where((row) => row.id.equals(legacyCategoryId) &
                    row.profileId.equals(profileId)))
              .getSingleOrNull();
          final catId = legacyCategory?.id ??
              const Uuid().v5(Namespace.url.value, 'ledgerpulse:$profileId:category:$categoryKey');
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

    // 7. Trigger background sync after transaction commit
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
  Future<void> deleteProfile(String profileId) => _setProfileDeleted(profileId, true);

  @override
  Future<void> restoreProfile(String profileId) => _setProfileDeleted(profileId, false);

  Future<void> _setProfileDeleted(String profileId, bool deleted) async {
    final actor = supabaseClient?.auth.currentUser?.id ?? db.userId;
    if (actor != db.userId) {
      throw StateError('Workspace database belongs to a different account.');
    }
    await db.transaction(() async {
      final workspace = await (db.select(db.profiles)..where(
        (p) => p.id.equals(profileId) & p.ownerId.equals(actor))).getSingleOrNull();
      if (workspace == null) throw StateError('Workspace is unavailable to this account.');
      if (workspace.isDeleted == deleted) return;
      final now = DateTime.now();
      await (db.update(db.profiles)..where((t) => t.id.equals(profileId))).write(
        ProfilesCompanion(
          isDeleted: Value(deleted),
          syncStatus: const Value(SyncRecordStatus.pending),
          updatedAt: Value(now),
        ),
      );
      await enqueueMutation(
        db: db,
        table: 'profiles',
        recordId: profileId,
        type: 'UPSERT',
        fullRowMap: {
          'id': profileId,
          'owner_id': actor,
          'is_deleted': deleted,
          'updated_at': encodeTime(now),
        },
      );

      // Also soft-delete linked company if one exists
      final comp = await (db.select(db.companies)
            ..where((c) => c.profileId.equals(profileId) |
                (c.profileId.isNull() & c.id.equals(profileId))))
          .getSingleOrNull();
      if (comp != null) {
        if (comp.ownerId != null && comp.ownerId != actor) {
          throw StateError('Linked company belongs to a different account.');
        }
        await (db.update(db.companies)..where((t) => t.id.equals(comp.id))).write(
          CompaniesCompanion(
            isDeleted: Value(deleted),
            syncStatus: const Value(SyncRecordStatus.pending),
            updatedAt: Value(now),
          ),
        );
        await enqueueMutation(
          db: db,
          table: 'companies',
          recordId: comp.id,
          type: 'UPSERT',
          fullRowMap: {
            'id': comp.id,
            'profile_id': profileId,
            'owner_id': actor,
            'is_deleted': deleted,
            'isDeleted': deleted,
            'updated_at': encodeTime(now),
            'updatedAt': encodeTime(now),
          },
        );
      }
    });
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
    final lastActiveId = prefs?.getString(activeWorkspacePreferenceKey(userId)) ??
        prefs?.getString('last_active_company_id_$userId');

    if (profiles.length == 1) {
      final single = profiles.first;
      await prefs?.setString(activeWorkspacePreferenceKey(userId), single.id);
      if (!ref.mounted || ref.read(activeUserIdProvider) != userId) return;

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

  /// Keep visible profile headers synchronized after a local metadata edit.
  void updateProfileDetails(Company company) {
    final current = state;
    if (current is! ActiveProfileReadySessionState) return;
    WorkspaceProfileHeader updated(WorkspaceProfileHeader header) => header.id != company.id ? header :
      header.copyWith(name: company.name, legalName: company.legalName,
        currencyCode: company.currencyCode, gstin: company.gstin,
        updatedAt: company.updatedAt);
    _currentActiveProfile = updated(current.activeProfile);
    _currentAvailableProfiles = current.availableProfiles.map(updated).toList();
    state = ActiveProfileReadySessionState(
      userId: current.userId, activeProfile: _currentActiveProfile!,
      availableProfiles: _currentAvailableProfiles!,
      isOffline: current.isOffline,
    );
  }

  Future<void> removeDeletedProfile(String userId, String profileId) async {
    final current = state;
    if (current is! ActiveProfileReadySessionState || current.userId != userId) {
      return;
    }
    final remaining =
        current.availableProfiles.where((profile) => profile.id != profileId).toList();
    if (current.activeProfile.id == profileId) {
      if (remaining.isNotEmpty) await switchProfile(remaining.first);
      return;
    }

    _currentAvailableProfiles = remaining;
    state = current.isOffline
        ? OfflineActiveProfileReadySessionState(
            userId: userId,
            activeProfile: current.activeProfile,
            availableProfiles: remaining,
          )
        : ActiveProfileReadySessionState(
            userId: userId,
            activeProfile: current.activeProfile,
            availableProfiles: remaining,
          );
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
      if (!ref.mounted || ref.read(activeUserIdProvider) != userId) return;
      final isAuthorized = freshProfiles.any((p) => p.id == profile.id);
      if (!isAuthorized) {
        state = const SessionErrorState(
          'Access Revoked: Your access to this workspace has been removed.',
        );
        return;
      }

      final targetProfile = freshProfiles.firstWhere((p) => p.id == profile.id);
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs?.setString(activeWorkspacePreferenceKey(userId), targetProfile.id);
      if (!ref.mounted || ref.read(activeUserIdProvider) != userId) return;

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
    if (ref.mounted) {
      ref.read(userProfileProvider.notifier).showSelectedWorkspace(profile.id);
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
