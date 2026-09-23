import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/company_model.dart';
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

  void addCompany(Company newCompany) {
    final profileNotifier = ref.read(userProfileProvider.notifier);
    final currentProfile = ref.read(userProfileProvider);
    final updatedList = [...currentProfile.companies, newCompany];
    profileNotifier.updateProfile(
      currentProfile.copyWith(
        companies: updatedList,
        activeCompanyId: newCompany.id,
      ),
    );
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
