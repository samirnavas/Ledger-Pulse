import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_profile_model.dart';
import 'auth_providers.dart';
import 'ledger_providers.dart';

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final authState = ref.watch(authControllerProvider);
    final phone = authState.phoneNumber ?? '';
    
    final initial = UserProfile(
      id: 'usr_default',
      name: '',
      phoneNumber: phone,
      email: '',
      companies: const [],
    );

    // Asynchronously check and load persistent profile from database
    Future.microtask(() => _loadFromDatabase(initial.id));

    return initial;
  }

  Future<void> _loadFromDatabase(String userId) async {
    try {
      if (!ref.mounted) return;
      final repo = ref.read(driftLedgerRepositoryProvider);
      final loaded = await repo.getUserProfile(userId);
      if (loaded != null && ref.mounted) {
        state = loaded;
      }
    } catch (e, st) {
      debugPrint('UserProfileNotifier: Error loading profile from database: $e\n$st');
    }
  }

  void updateProfile(UserProfile updated) {
    state = updated;
    _saveToDatabase(updated);
  }

  Future<void> _saveToDatabase(UserProfile profile) async {
    try {
      if (!ref.mounted) return;
      final repo = ref.read(driftLedgerRepositoryProvider);
      await repo.saveUserProfile(profile);
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


