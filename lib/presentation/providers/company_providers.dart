import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/modules/module_catalog.dart';
import '../../data/models/company_model.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import 'auth_providers.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';
import 'subscription_providers.dart';


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

