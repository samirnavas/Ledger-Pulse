import '../models/workspace_profile_header.dart';

abstract class IProfileRepository {
  /// Fetches all accessible profiles for the current authenticated user/account.
  Future<List<WorkspaceProfileHeader>> getAccessibleProfiles(String accountId);

  /// Creates a new profile transactionally and idempotently via Supabase RPC or Drift fallback.
  Future<WorkspaceProfileHeader> createProfile({
    required String name,
    required ProfileType type,
    String currencyCode = 'INR',
    String? legalName,
    String? gstin,
    String? customId,
    String? accountId,
  });

  /// Deletes or soft-deletes a profile if caller is the owner.
  Future<void> deleteProfile(String profileId);
}

