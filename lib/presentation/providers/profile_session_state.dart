import 'package:flutter/foundation.dart';
import '../../domain/models/workspace_profile_header.dart';

@immutable
abstract class ProfileSessionState {
  const ProfileSessionState();
}

class UnauthenticatedSessionState extends ProfileSessionState {
  const UnauthenticatedSessionState();
}

class AuthenticatingSessionState extends ProfileSessionState {
  const AuthenticatingSessionState();
}

class LoadingProfilesSessionState extends ProfileSessionState {
  final String userId;
  const LoadingProfilesSessionState(this.userId);
}

class OnboardingRequiredSessionState extends ProfileSessionState {
  final String userId;
  const OnboardingRequiredSessionState(this.userId);
}

class ProfileSelectionRequiredSessionState extends ProfileSessionState {
  final String userId;
  final List<WorkspaceProfileHeader> profiles;
  const ProfileSelectionRequiredSessionState({
    required this.userId,
    required this.profiles,
  });
}

class ActiveProfileReadySessionState extends ProfileSessionState {
  final String userId;
  final WorkspaceProfileHeader activeProfile;
  final List<WorkspaceProfileHeader> availableProfiles;
  const ActiveProfileReadySessionState({
    required this.userId,
    required this.activeProfile,
    required this.availableProfiles,
  });
}

class SessionErrorState extends ProfileSessionState {
  final String message;
  final bool isNetworkError;
  const SessionErrorState(this.message, {this.isNetworkError = false});
}

