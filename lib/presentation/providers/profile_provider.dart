import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database.dart';
import '../../data/local/outbox_helper.dart';
import '../../data/models/company_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/models/user_profile_model.dart';
import 'auth_providers.dart';
import 'database_providers.dart';

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final uid = ref.watch(activeUserIdProvider);
    final authState = ref.watch(authControllerProvider);
    final phone = authState.phoneNumber ?? '';
    final name = authState.userName ?? '';
    final email = authState.email ?? '';
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedActiveCompanyId = prefs?.getString('last_active_company_id_$uid') ??
        prefs?.getString('last_active_company_id');

    final initial = UserProfile(
      id: uid,
      name: name,
      phoneNumber: phone,
      email: email,
      companies: const [],
      activeCompanyId: (savedActiveCompanyId != null && savedActiveCompanyId.isNotEmpty)
          ? savedActiveCompanyId
          : null,
    );

    // Asynchronously check and load persistent profile from database
    Future.microtask(() => _loadFromDatabase(initial.id));

    return initial;
  }

  Future<void> _loadFromDatabase(String userId) async {
    try {
      if (!ref.mounted) return;
      final db = ref.read(appDatabaseProvider);
      final authState = ref.read(authControllerProvider);

      final profileRow = await (db.select(db.userProfiles)
            ..where((t) => t.id.equals(userId) & t.isDeleted.equals(false)))
          .getSingleOrNull();

      final companyRows = await (db.select(db.companies)
            ..where((c) => c.isDeleted.equals(false)))
          .get();

      final loadedCompanies = companyRows.map((c) => Company(
        id: c.id,
        name: c.name,
        legalName: c.legalName,
        gstin: c.gstin,
        address: c.address,
        dealerType: c.dealerType,
        currencyCode: c.currencyCode,
        mode: CompanyMode.tryParse(c.mode) ?? CompanyMode.ledger,
        phoneNumber: c.phoneNumber,
        email: c.email,
        bankName: c.bankName,
        bankAccountNumber: c.bankAccountNumber,
        bankIfsc: c.bankIfsc,
        upiId: c.upiId,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
      )).toList();

      if (!ref.mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final savedActiveId = prefs?.getString('last_active_company_id_$userId') ??
          prefs?.getString('last_active_company_id');

      final effectiveActiveId = (savedActiveId != null && savedActiveId.isNotEmpty)
          ? savedActiveId
          : (state.activeCompanyId.isNotEmpty
              ? state.activeCompanyId
              : (profileRow?.activeCompanyId ??
                  (loadedCompanies.isNotEmpty ? loadedCompanies.first.id : '')));

      final activeComp = loadedCompanies.where((c) => c.id == effectiveActiveId).firstOrNull ??
          (loadedCompanies.isNotEmpty ? loadedCompanies.first : null);

      final effectiveName = (profileRow != null && profileRow.name.isNotEmpty)
          ? profileRow.name
          : (authState.userName?.isNotEmpty == true ? authState.userName! : state.name);

      final effectivePhone = (profileRow != null && profileRow.phoneNumber.isNotEmpty)
          ? profileRow.phoneNumber
          : (authState.phoneNumber?.isNotEmpty == true ? authState.phoneNumber! : state.phoneNumber);

      final effectiveEmail = (profileRow != null && profileRow.email.isNotEmpty)
          ? profileRow.email
          : (authState.email?.isNotEmpty == true ? authState.email! : state.email);

      final effectiveBusinessName = (profileRow != null && profileRow.businessName?.isNotEmpty == true)
          ? profileRow.businessName!
          : (activeComp?.name.isNotEmpty == true ? activeComp!.name : state.businessName);

      final effectiveGstin = (profileRow != null && profileRow.gstin?.isNotEmpty == true)
          ? profileRow.gstin!
          : (activeComp?.gstin ?? state.gstin);

      final effectiveAddress = (profileRow != null && profileRow.address?.isNotEmpty == true)
          ? profileRow.address!
          : (activeComp?.address ?? state.address);

      Role userRole = Role.admin;
      if (profileRow != null) {
        try {
          userRole = Role.values.byName(profileRow.role.toLowerCase());
        } catch (_) {}
      }

      if (ref.mounted) {
        state = UserProfile(
          id: profileRow?.id ?? userId,
          name: effectiveName,
          phoneNumber: effectivePhone,
          email: effectiveEmail,
          businessName: effectiveBusinessName,
          address: effectiveAddress,
          gstin: effectiveGstin,
          businessType: profileRow?.businessType ?? state.businessType,
          bankName: profileRow?.bankName ?? activeComp?.bankName ?? state.bankName,
          bankAccountNumber: profileRow?.bankAccountNumber ??
              activeComp?.bankAccountNumber ??
              state.bankAccountNumber,
          bankIfsc: profileRow?.bankIfsc ?? activeComp?.bankIfsc ?? state.bankIfsc,
          upiId: profileRow?.upiId ?? activeComp?.upiId ?? state.upiId,
          role: userRole,
          activeCompanyId: effectiveActiveId,
          companies: loadedCompanies.isNotEmpty ? loadedCompanies : state.companies,
        );

        if (savedActiveId == null && effectiveActiveId.isNotEmpty) {
          prefs?.setString('last_active_company_id_$userId', effectiveActiveId);
        }
      }
    } catch (e, st) {
      debugPrint('UserProfileNotifier: Error loading profile from database: $e\n$st');
    }
  }

  void updateProfile(UserProfile updated) {
    state = updated;
    if (updated.activeCompanyId.isNotEmpty) {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs?.setString('last_active_company_id_${updated.id}', updated.activeCompanyId);
    }
    _saveToDatabase(updated);
  }

  Future<void> _saveToDatabase(UserProfile profile) async {
    try {
      if (!ref.mounted) return;
      final db = ref.read(appDatabaseProvider);
      final now = DateTime.now();

      final profileCompanion = UserProfilesCompanion.insert(
        id: profile.id,
        name: profile.name,
        phoneNumber: profile.phoneNumber,
        email: profile.email,
        businessName: Value(profile.businessName),
        address: Value(profile.address),
        gstin: Value(profile.gstin),
        businessType: Value(profile.businessType),
        bankName: Value(profile.bankName),
        bankAccountNumber: Value(profile.bankAccountNumber),
        bankIfsc: Value(profile.bankIfsc),
        upiId: Value(profile.upiId),
        activeCompanyId: Value(profile.activeCompanyId.isNotEmpty ? profile.activeCompanyId : 'cmp_default'),
        role: Value(profile.role.name),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      );
      await db.into(db.userProfiles).insertOnConflictUpdate(profileCompanion);

      // Enqueue sync outbox mutation for user_profiles
      await enqueueMutation(
        db: db,
        table: 'user_profiles',
        recordId: profile.id,
        type: 'UPSERT',
        fullRowMap: {
          'id': profile.id,
          'name': profile.name,
          'phoneNumber': profile.phoneNumber,
          'email': profile.email,
          'businessName': profile.businessName,
          'address': profile.address,
          'gstin': profile.gstin,
          'businessType': profile.businessType,
          'bankName': profile.bankName,
          'bankAccountNumber': profile.bankAccountNumber,
          'bankIfsc': profile.bankIfsc,
          'upiId': profile.upiId,
          'activeCompanyId': profile.activeCompanyId.isNotEmpty ? profile.activeCompanyId : 'cmp_default',
          'role': profile.role.name,
          'isDeleted': false,
          'updatedAt': now,
        },
      );

      // Update associated company in db.companies if present
      if (profile.activeCompanyId.isNotEmpty) {
        final existingComp = await (db.select(db.companies)
              ..where((c) => c.id.equals(profile.activeCompanyId)))
            .getSingleOrNull();
        if (existingComp != null) {
          final compName = profile.businessName.isNotEmpty ? profile.businessName : existingComp.name;
          await (db.update(db.companies)..where((c) => c.id.equals(profile.activeCompanyId))).write(
            CompaniesCompanion(
              name: Value(compName),
              legalName: Value(compName),
              gstin: Value(profile.gstin.isNotEmpty ? profile.gstin : existingComp.gstin),
              address: Value(profile.address.isNotEmpty ? profile.address : existingComp.address),
              bankName: Value(profile.bankName ?? existingComp.bankName),
              bankAccountNumber: Value(profile.bankAccountNumber ?? existingComp.bankAccountNumber),
              bankIfsc: Value(profile.bankIfsc ?? existingComp.bankIfsc),
              upiId: Value(profile.upiId ?? existingComp.upiId),
              updatedAt: Value(now),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

          await enqueueMutation(
            db: db,
            table: 'companies',
            recordId: existingComp.id,
            type: 'UPSERT',
            fullRowMap: {
              'id': existingComp.id,
              'name': compName,
              'legalName': compName,
              'gstin': profile.gstin.isNotEmpty ? profile.gstin : existingComp.gstin,
              'address': profile.address.isNotEmpty ? profile.address : existingComp.address,
              'bankName': profile.bankName ?? existingComp.bankName,
              'bankAccountNumber': profile.bankAccountNumber ?? existingComp.bankAccountNumber,
              'bankIfsc': profile.bankIfsc ?? existingComp.bankIfsc,
              'upiId': profile.upiId ?? existingComp.upiId,
              'ownerId': existingComp.ownerId,
              'mode': existingComp.mode,
              'currencyCode': existingComp.currencyCode,
              'isActive': existingComp.isActive,
              'isDeleted': existingComp.isDeleted,
              'updatedAt': now,
            },
          );
        }
      }

      // Trigger background sync
      try {
        ref.read(syncEngineProvider).triggerBackgroundSync();
      } catch (_) {}
    } catch (e, st) {
      debugPrint('UserProfileNotifier: Error saving profile to database: $e\n$st');
    }
  }

  Future<void> syncProfileToDatabase() async {
    await _saveToDatabase(state);
  }

  Future<void> reloadFromDatabase() async {
    await _loadFromDatabase(state.id);
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);

class IsProfileEditingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEditing(bool editing) => state = editing;
}

final isProfileEditingProvider =
    NotifierProvider<IsProfileEditingNotifier, bool>(IsProfileEditingNotifier.new);

class HasProfileChangesNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setHasChanges(bool hasChanges) => state = hasChanges;
}

final hasProfileChangesProvider =
    NotifierProvider<HasProfileChangesNotifier, bool>(HasProfileChangesNotifier.new);

class ProfileSaveActionNotifier extends Notifier<VoidCallback?> {
  @override
  VoidCallback? build() => null;

  void setAction(VoidCallback? action) => state = action;
}

final profileSaveActionProvider =
    NotifierProvider<ProfileSaveActionNotifier, VoidCallback?>(ProfileSaveActionNotifier.new);

class ProfileCancelActionNotifier extends Notifier<VoidCallback?> {
  @override
  VoidCallback? build() => null;

  void setAction(VoidCallback? action) => state = action;
}

final profileCancelActionProvider =
    NotifierProvider<ProfileCancelActionNotifier, VoidCallback?>(ProfileCancelActionNotifier.new);
