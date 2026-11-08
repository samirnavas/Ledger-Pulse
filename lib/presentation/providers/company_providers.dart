import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/modules/module_catalog.dart';
import '../../data/models/company_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/models/user_profile_model.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import 'auth_providers.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';
import 'subscription_providers.dart';


/// Provider for current user's active company ID, backing repository scoping without circular dependency.
final activeCompanyIdProvider = Provider<String>((ref) {
  final profileActiveId = ref.watch(userProfileProvider.select((p) => p.activeCompanyId));
  if (profileActiveId.isNotEmpty) {
    return profileActiveId;
  }
  final authRepo = ref.watch(authRepositoryProvider);
  final uid = authRepo.currentUserId ?? 'usr_default';
  final prefs = ref.watch(sharedPreferencesProvider);
  final savedId = prefs?.getString('last_active_company_id_$uid') ??
      prefs?.getString('last_active_company_id');
  return (savedId != null && savedId.isNotEmpty) ? savedId : 'cmp_default';
});

/// Provider for non-deleted companies directly from the Companies table (single source of truth).
/// Automatically refreshed on repository updates.
final companiesProvider = FutureProvider<List<Company>>((ref) async {
  final repo = ref.watch(driftLedgerRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  return await repo.getCompanies();
});

/// Derives user companies from the Companies table via [companiesProvider].
final userCompaniesProvider = Provider<List<Company>>((ref) {
  final asyncCompanies = ref.watch(companiesProvider);
  final profileCompanies = ref.watch(userProfileProvider.select((p) => p.companies));
  if (asyncCompanies.hasValue && asyncCompanies.value != null && asyncCompanies.value!.isNotEmpty) {
    return asyncCompanies.value!;
  }
  return profileCompanies;
});

/// Derives the active company from [userCompaniesProvider] and activeCompanyId from user profile.
final activeCompanyProvider = Provider<Company>((ref) {
  final companies = ref.watch(userCompaniesProvider);
  final activeCompanyId = ref.watch(userProfileProvider.select((p) => p.activeCompanyId));
  if (companies.isEmpty) {
    return Company(
      id: activeCompanyId,
      name: '',
      legalName: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  // 1. Try to match currently set activeCompanyId
  final profileMatch = companies.where((c) => c.id == activeCompanyId).firstOrNull;
  if (profileMatch != null) return profileMatch;

  // 2. Try to match persisted last_active_company_id from SharedPreferences
  final prefs = ref.watch(sharedPreferencesProvider);
  final savedId = prefs?.getString('last_active_company_id');
  if (savedId != null && savedId.isNotEmpty) {
    final savedMatch = companies.where((c) => c.id == savedId).firstOrNull;
    if (savedMatch != null) return savedMatch;
  }

  return companies.first;
});

class CompanyController extends Notifier<void> {
  @override
  void build() {}

  /// Bootstraps the initial company/profile for a newly signed-up user.
  /// Automatically seeds accounts and connects to local Drift DB & Supabase outbox.
  Future<Company> bootstrapInitialProfile({
    required String name,
    required String email,
    required bool isCompanyAccount,
    CompanyMode? mode,
  }) async {
    final repo = ref.read(driftLedgerRepositoryProvider);
    final authRepo = ref.read(authRepositoryProvider);
    final uid = authRepo.currentUserId ?? 'usr_default';

    final effectiveMode = mode ??
        (isCompanyAccount ? CompanyMode.ledger : CompanyMode.expenseTracker);

    final companyId = 'cmp_${DateTime.now().millisecondsSinceEpoch}';
    final trimmedName = name.trim();
    final displayName = trimmedName.isNotEmpty
        ? trimmedName
        : (effectiveMode == CompanyMode.ledger ? 'My Business' : 'Personal Expenses');

    final newCompany = Company(
      id: companyId,
      name: displayName,
      legalName: displayName,
      currencyCode: 'INR',
      mode: effectiveMode,
      enabledModules: ModuleCatalog.defaultsFor(effectiveMode),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 1. Create company in DB (seeds accounts, records outbox for Supabase)
    await repo.createCompany(newCompany);

    // 2. Create user profile in DB (records outbox for Supabase)
    final profile = UserProfile(
      id: uid,
      name: trimmedName.isNotEmpty ? trimmedName : 'User',
      email: email.trim(),
      phoneNumber: authRepo.currentPhoneNumber ?? '',
      businessName: effectiveMode == CompanyMode.ledger ? displayName : null,
      activeCompanyId: companyId,
      companies: [newCompany],
      role: Role.admin,
    );
    await repo.saveUserProfile(profile);

    // 3. Persist active company selection in SharedPreferences
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setString('last_active_company_id_$uid', companyId);
    await prefs?.setString('last_active_company_id', companyId);

    // 4. Update Riverpod state immediately
    ref.read(userProfileProvider.notifier).updateProfile(profile);
    ref.invalidate(companiesProvider);

    // 5. Trigger sync in background to connect to remote Supabase tables
    try {
      ref.read(syncEngineProvider).triggerBackgroundSync();
    } catch (_) {}

    return newCompany;
  }

  /// Ensures that the current authenticated user has at least one company in the database.
  /// If none exists, attempts to pull from Supabase first. If still empty, bootstraps a default profile.
  Future<void> ensureProfileAndCompanyExist({
    String? name,
    String? email,
    String? phone,
    bool isCompanyAccount = true,
  }) async {
    final repo = ref.read(driftLedgerRepositoryProvider);
    var companies = await repo.getCompanies();

    if (companies.isNotEmpty) {
      final currentActiveId = ref.read(activeCompanyIdProvider);
      if (!companies.any((c) => c.id == currentActiveId)) {
        await selectCompany(companies.first.id);
      }
      return;
    }

    // Try pulling from Supabase first (in case data already exists remotely)
    try {
      final engine = ref.read(syncEngineProvider);
      await engine.syncAll(companyId: 'cmp_default');
      companies = await repo.getCompanies();
      if (companies.isNotEmpty) {
        await ref.read(userProfileProvider.notifier).reloadFromDatabase();
        ref.invalidate(companiesProvider);
        final profile = ref.read(userProfileProvider);
        if (profile.activeCompanyId.isNotEmpty &&
            companies.any((c) => c.id == profile.activeCompanyId)) {
          await selectCompany(profile.activeCompanyId);
        } else {
          await selectCompany(companies.first.id);
        }
        return;
      }
    } catch (e) {
      debugPrint('ensureProfileAndCompanyExist pull notice: $e');
    }

    // Still empty -> do not silently bootstrap a Ledger profile or any company.
    // The user has 0 profiles and must be routed to profile onboarding.
    return;
  }

  Future<void> selectCompany(String companyId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs?.setString('last_active_company_id', companyId);

    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    profileNotifier.updateProfile(
      currentProfile.copyWith(activeCompanyId: companyId),
    );
  }

  Future<void> addCompany(
    Company newCompany, {
    Map<String, int>? initialWalletBalancesInCents,
  }) async {
    // Enforce SubscriptionTier.maxCompanies on creation
    final currentTier = ref.read(currentSubscriptionTierProvider);
    final existingCompanies = ref.read(userCompaniesProvider);
    if (existingCompanies.length >= currentTier.maxCompanies) {
      throw CompanyLimitExceededException(currentTier);
    }

    // 1. Write via the repository first
    final repo = ref.read(driftLedgerRepositoryProvider);
    await repo.createCompany(
      newCompany,
      initialWalletBalancesInCents: initialWalletBalancesInCents,
    );

    ref.invalidate(companiesProvider);

    // 2. On success, update state
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    profileNotifier.updateProfile(
      currentProfile.copyWith(
        companies: [...currentProfile.companies, newCompany],
        activeCompanyId: newCompany.id,
      ),
    );
  }

  Future<void> updateCompany(Company updatedCompany) async {
    // 1. Write via the repository first
    final repo = ref.read(driftLedgerRepositoryProvider);
    await repo.updateCompany(updatedCompany);

    ref.invalidate(companiesProvider);

    // State is derived from companies table so activeCompanyProvider & userCompaniesProvider
    // automatically refresh on repo update. If userProfile has in-memory companies, update them too.
    final currentProfile = ref.read(userProfileProvider);
    if (currentProfile.companies.isNotEmpty) {
      final updatedList = currentProfile.companies.map((c) {
        if (c.id == updatedCompany.id) {
          return updatedCompany;
        }
        return c;
      }).toList();
      ref.read(userProfileProvider.notifier).updateProfile(
        currentProfile.copyWith(companies: updatedList),
      );
    }
  }

  Future<Company> upgradeToLedger(
    String companyId, {
    String preset = ModulePresets.billingAndGst,
    Set<AppModule>? modules,
  }) async {
    final repo = ref.read(driftLedgerRepositoryProvider);
    final upgradedCompany = await repo.upgradeToLedger(
      companyId,
      preset: preset,
      modules: modules,
    );

    ref.invalidate(companiesProvider);

    final currentProfile = ref.read(userProfileProvider);
    if (currentProfile.companies.isNotEmpty) {
      final updatedList = currentProfile.companies.map((c) {
        if (c.id == upgradedCompany.id) {
          return upgradedCompany;
        }
        return c;
      }).toList();
      ref.read(userProfileProvider.notifier).updateProfile(
        currentProfile.copyWith(companies: updatedList),
      );
    }

    return upgradedCompany;
  }

  Future<bool> deleteCompany(String companyId) async {
    final companies = ref.read(userCompaniesProvider);
    if (companies.length <= 1) {
      return false;
    }

    // 1. Write via the repository first
    final repo = ref.read(driftLedgerRepositoryProvider);
    await repo.deleteCompany(companyId);

    ref.invalidate(companiesProvider);

    // 2. Update state if the active company was deleted
    final currentProfile = ref.read(userProfileProvider);
    final remaining = currentProfile.companies.where((c) => c.id != companyId).toList();
    String newActiveId = currentProfile.activeCompanyId;
    if (newActiveId == companyId) {
      newActiveId = remaining.isNotEmpty ? remaining.first.id : (companies.where((c) => c.id != companyId).firstOrNull?.id ?? '');
    }
    ref.read(userProfileProvider.notifier).updateProfile(
      currentProfile.copyWith(
        companies: remaining,
        activeCompanyId: newActiveId,
      ),
    );

    return true;
  }

  Future<void> updateCompanySettings({
    required String companyId,
    bool? isCloudSyncEnabled,
    bool? isDropboxSyncEnabled,
  }) async {
    final companies = ref.read(userCompaniesProvider);
    final existing = companies.firstWhere(
      (c) => c.id == companyId,
      orElse: () => Company(
        id: companyId,
        name: '',
        legalName: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final updated = existing.copyWith(
      isCloudSyncEnabled: isCloudSyncEnabled ?? existing.isCloudSyncEnabled,
      isDropboxSyncEnabled: isDropboxSyncEnabled ?? existing.isDropboxSyncEnabled,
      updatedAt: DateTime.now(),
    );

    final repo = ref.read(driftLedgerRepositoryProvider);
    await repo.updateCompany(updated);
  }

  /// Enables or disables an [AppModule] for [companyId].
  ///
  /// Refuses to enable when dependencies are disabled (throws [ModuleDependencyException],
  /// or returns missing dependencies when [throwOnError] is false).
  /// Refuses to disable when active enabled modules depend on it (throws [ModuleDependencyException],
  /// or returns active dependents when [throwOnError] is false).
  ///
  /// On success, persists DB first via repository, bumps updatedAt, writes audit and outbox,
  /// refreshes state, and returns an empty set.
  Future<Set<AppModule>> setModuleEnabled(
    String companyId,
    AppModule module,
    bool enabled, {
    bool throwOnError = true,
  }) async {
    final repo = ref.read(driftLedgerRepositoryProvider);
    final companies = await repo.getCompanies();
    final existing = companies.firstWhere(
      (c) => c.id == companyId,
      orElse: () {
        final inMemory = ref.read(userCompaniesProvider);
        return inMemory.firstWhere(
          (c) => c.id == companyId,
          orElse: () => throw ArgumentError('Company not found: $companyId'),
        );
      },
    );

    if (enabled) {
      if (!ModuleCatalog.isModeAllowed(existing.mode, module)) {
        if (throwOnError) {
          throw ModuleDependencyException(
            'Module ${module.name} is not allowed in ${existing.mode.name} mode',
          );
        }
        return {module};
      }

      final missing = ModuleCatalog.missingDependencies(module, existing.enabledModules);
      if (missing.isNotEmpty) {
        if (throwOnError) {
          throw ModuleDependencyException(
            'Cannot enable ${module.name}: required dependencies are disabled (${missing.map((m) => m.name).join(', ')})',
            missingDependencies: missing,
          );
        }
        return missing;
      }
    } else {
      final dependents = ModuleCatalog.dependentsOf(module);
      final activeDependents = dependents.intersection(existing.enabledModules);
      if (activeDependents.isNotEmpty) {
        if (throwOnError) {
          throw ModuleDependencyException(
            'Cannot disable ${module.name}: active modules depend on it (${activeDependents.map((m) => m.name).join(', ')})',
            activeDependents: activeDependents,
          );
        }
        return activeDependents;
      }
    }

    final newModules = Set<AppModule>.from(existing.enabledModules);
    if (enabled) {
      newModules.add(module);
    } else {
      newModules.remove(module);
    }

    final updated = existing.copyWith(
      enabledModules: newModules,
      updatedAt: DateTime.now(),
    );

    // 1. Write via the repository first (DB, outbox, audit, bumps updatedAt)
    await repo.updateCompany(updated);

    ref.invalidate(companiesProvider);

    // 2. On success, update in-memory profile state if present
    final currentProfile = ref.read(userProfileProvider);
    if (currentProfile.companies.isNotEmpty) {
      final updatedList = currentProfile.companies.map((c) {
        if (c.id == updated.id) {
          return updated;
        }
        return c;
      }).toList();
      ref.read(userProfileProvider.notifier).updateProfile(
        currentProfile.copyWith(companies: updatedList),
      );
    }

    return const {};
  }
}

/// Thrown when enabling or disabling a module violates dependency constraints.
class ModuleDependencyException implements Exception {
  final String message;
  final Set<AppModule> missingDependencies;
  final Set<AppModule> activeDependents;

  const ModuleDependencyException(
    this.message, {
    this.missingDependencies = const {},
    this.activeDependents = const {},
  });

  @override
  String toString() => message;
}


final companyControllerProvider =
    NotifierProvider<CompanyController, void>(CompanyController.new);

