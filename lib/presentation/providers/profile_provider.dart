import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/drift_ledger_repository.dart';
import '../../data/models/user_profile_model.dart';
import 'auth_providers.dart';
import 'database_providers.dart';

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final authState = ref.watch(authControllerProvider);
    final phone = authState.phoneNumber ?? '+91 98765 43210';
    
    final initial = UserProfile(
      id: 'usr_default',
      name: 'Samir Navas',
      businessName: 'Ledger Pulse Enterprise',
      phoneNumber: phone,
      email: 'samir.navas@example.com',
      address: 'Suite 402, Trade Tower, Bangalore, India',
      gstin: '29ABCDE1234F1ZH',
      businessType: 'Retail & Wholesale',
    );

    // Asynchronously check and load persistent profile from database
    Future.microtask(() => _loadFromDatabase(initial.id));

    return initial;
  }

  Future<void> _loadFromDatabase(String userId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final syncEngine = ref.read(syncEngineProvider);
      final repo = DriftLedgerRepository(db: db, syncEngine: syncEngine, currentUserId: userId);
      final loaded = await repo.getUserProfile(userId);
      if (loaded != null) {
        state = loaded;
      }
    } catch (e) {
      debugPrint('UserProfileNotifier: Error loading profile from database: $e');
    }
  }

  void updateProfile(UserProfile updated) {
    state = updated;
    _saveToDatabase(updated);
  }

  Future<void> _saveToDatabase(UserProfile profile) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final syncEngine = ref.read(syncEngineProvider);
      final repo = DriftLedgerRepository(db: db, syncEngine: syncEngine, currentUserId: profile.id);
      await repo.saveUserProfile(profile);
    } catch (e) {
      debugPrint('UserProfileNotifier: Error saving profile to database: $e');
    }
  }

  Future<void> syncProfileToDatabase() async {
    await _saveToDatabase(state);
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

