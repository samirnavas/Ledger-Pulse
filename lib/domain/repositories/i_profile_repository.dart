import '../models/workspace_profile_header.dart';

abstract class IProfileRepository {
  /// Fetches all accessible profiles for the current authenticated user/account from local persistence.
  Future<List<WorkspaceProfileHeader>> getAccessibleProfiles(String accountId);

  /// Synchronizes and loads remote workspaces, memberships, and user profile from Supabase
  /// into the local Drift database, returning the fresh list of accessible profiles.
  Future<List<WorkspaceProfileHeader>> syncAndLoadRemoteWorkspaces(String accountId);

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

