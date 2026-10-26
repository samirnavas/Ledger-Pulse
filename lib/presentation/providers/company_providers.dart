import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/company_model.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';

final activeCompanyProvider = Provider<Company>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile.activeCompany;
});

final userCompaniesProvider = Provider<List<Company>>((ref) {
  final profile = ref.watch(userProfileProvider);
  if (profile.companies.isEmpty) {
    return [profile.activeCompany];
  }
  return profile.companies;
});

class CompanyController extends Notifier<void> {
  @override
  void build() {}

  void selectCompany(String companyId) {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    profileNotifier.updateProfile(
      currentProfile.copyWith(activeCompanyId: companyId),
    );
  }

  Future<void> addCompany(Company newCompany) async {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    final updatedList = [...currentProfile.companies, newCompany];
    profileNotifier.updateProfile(
      currentProfile.copyWith(
        companies: updatedList,
        activeCompanyId: newCompany.id,
      ),
    );
    try {
      final repo = ref.read(driftLedgerRepositoryProvider);
      await repo.createCompany(newCompany);
    } catch (_) {}
  }

  Future<void> updateCompany(Company updatedCompany) async {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    final updatedList = currentProfile.companies.map((c) {
      if (c.id == updatedCompany.id) {
        return updatedCompany;
      }
      return c;
    }).toList();

    profileNotifier.updateProfile(
      currentProfile.copyWith(
        companies: updatedList,
      ),
    );
    try {
      final repo = ref.read(driftLedgerRepositoryProvider);
      await repo.updateCompany(updatedCompany);
    } catch (_) {}
  }

  Future<bool> deleteCompany(String companyId) async {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);

    if (currentProfile.companies.length <= 1) {
      return false;
    }

    final updatedList =
        currentProfile.companies.where((c) => c.id != companyId).toList();
    String newActiveId = currentProfile.activeCompanyId;
    if (newActiveId == companyId) {
      newActiveId = updatedList.first.id;
    }

    profileNotifier.updateProfile(
      currentProfile.copyWith(
        companies: updatedList,
        activeCompanyId: newActiveId,
      ),
    );

    try {
      final repo = ref.read(driftLedgerRepositoryProvider);
      await repo.deleteCompany(companyId);
    } catch (_) {}

    return true;
  }

  void updateCompanySettings({
    required String companyId,
    bool? isCloudSyncEnabled,
    bool? isDropboxSyncEnabled,
  }) {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    final updatedList = currentProfile.companies.map((c) {
      if (c.id == companyId) {
        return c.copyWith(
          isCloudSyncEnabled: isCloudSyncEnabled ?? c.isCloudSyncEnabled,
          isDropboxSyncEnabled: isDropboxSyncEnabled ?? c.isDropboxSyncEnabled,
          updatedAt: DateTime.now(),
        );
      }
      return c;
    }).toList();

    profileNotifier.updateProfile(
      currentProfile.copyWith(companies: updatedList),
    );
  }
}

final companyControllerProvider =
    NotifierProvider<CompanyController, void>(CompanyController.new);

