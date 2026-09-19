import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_profile_model.dart';
import 'auth_providers.dart';

class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    final authState = ref.watch(authControllerProvider);
    final phone = authState.phoneNumber ?? '+91 98765 43210';
    
    return UserProfile(
      name: 'Samir Navas',
      businessName: 'Ledger Pulse Enterprise',
      phoneNumber: phone,
      email: 'samir.navas@example.com',
      address: 'Suite 402, Trade Tower, Bangalore, India',
      gstin: '29ABCDE1234F1ZH',
      businessType: 'Retail & Wholesale',
    );
  }

  void updateProfile(UserProfile updated) {
    state = updated;
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);
