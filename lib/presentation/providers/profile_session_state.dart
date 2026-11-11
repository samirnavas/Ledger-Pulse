import 'package:flutter/foundation.dart';
import '../../domain/models/workspace_profile_header.dart';

@immutable
abstract class ProfileSessionState {
  const ProfileSessionState();
}

/// Initializing state while the application is determining the auth state and restoring the session.
class SessionInitializingState extends ProfileSessionState {
  const SessionInitializingState();
}

/// Base unauthenticated session state (e.g. guest mode or signed out).
class UnauthenticatedSessionState extends ProfileSessionState {
  const UnauthenticatedSessionState();
}

/// Explicit Guest Ready state (subclass of UnauthenticatedSessionState for backwards compatibility).
class GuestReadySessionState extends UnauthenticatedSessionState {
  const GuestReadySessionState();
}

/// Transient state while authenticating credentials with Supabase.
class AuthenticatingSessionState extends ProfileSessionState {
  const AuthenticatingSessionState();
}

/// Authenticated user session is active, currently loading remote workspaces and profile.
class LoadingProfilesSessionState extends ProfileSessionState {
  final String userId;
  const LoadingProfilesSessionState(this.userId);
}

/// User is authenticated, but no accessible workspaces exist locally or remotely.
class OnboardingRequiredSessionState extends ProfileSessionState {
  final String userId;
  const OnboardingRequiredSessionState(this.userId);
}

/// Explicit representation for zero accessible workspaces (alias of OnboardingRequiredSessionState).
class NoAccessibleWorkspaceSessionState extends OnboardingRequiredSessionState {
  const NoAccessibleWorkspaceSessionState(super.userId);
}

/// Multiple accessible workspaces exist and user needs to choose which one to enter.
class ProfileSelectionRequiredSessionState extends ProfileSessionState {
  final String userId;
  final List<WorkspaceProfileHeader> profiles;
  const ProfileSelectionRequiredSessionState({
    required this.userId,
    required this.profiles,
  });
}

/// Authenticated session with an active workspace established.
class ActiveProfileReadySessionState extends ProfileSessionState {
  final String userId;
  final WorkspaceProfileHeader activeProfile;
  final List<WorkspaceProfileHeader> availableProfiles;
  final bool isOffline;

  const ActiveProfileReadySessionState({
    required this.userId,
    required this.activeProfile,
    required this.availableProfiles,
    this.isOffline = false,
  });
}

/// Explicit offline representation with cached workspace.
class OfflineActiveProfileReadySessionState extends ActiveProfileReadySessionState {
  const OfflineActiveProfileReadySessionState({
    required super.userId,
    required super.activeProfile,
    required super.availableProfiles,
  }) : super(isOffline: true);
}

/// Authentication session expired or invalidated.
class AuthExpiredSessionState extends UnauthenticatedSessionState {
  final String? message;
  const AuthExpiredSessionState([this.message]);
}

/// Error state encountered during session initialization or workspace loading.
class SessionErrorState extends ProfileSessionState {
  final String message;
  final bool isNetworkError;
  final bool isFatal;

  const SessionErrorState(
    this.message, {
    this.isNetworkError = false,
    this.isFatal = false,
  });

  bool get isRecoverable => !isFatal;
}
