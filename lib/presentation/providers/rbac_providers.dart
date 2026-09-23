import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/rbac_model.dart';
import '../../data/security/access_control_service.dart';
import 'profile_provider.dart';

final activeUserRoleProvider = Provider<Role>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile.role;
});

final rbacPermissionProvider = Provider.family<bool, UserAction>((ref, action) {
  final role = ref.watch(activeUserRoleProvider);
  return AccessControlService.hasPermission(role, action);
});
