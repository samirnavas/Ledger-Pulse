import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/modules/module_catalog.dart';
import '../../data/models/company_mode.dart';
import 'company_providers.dart';

/// Reason why an [AppModule] is locked or unavailable.
enum ModuleLockReason {
  modeNotAllowed,
  notEnabled,
  missingDependency,
}

/// Returns the lock reason for an [AppModule], or `null` if the module is unlocked and active.
final moduleLockReasonProvider = Provider.family<ModuleLockReason?, AppModule>((ref, module) {
  final company = ref.watch(activeCompanyProvider);

  // 1. Check whether active company's mode allows this module
  if (!ModuleCatalog.isModeAllowed(company.mode, module)) {
    return ModuleLockReason.modeNotAllowed;
  }

  // 2. Check if company has enabled this module
  if (!company.isModuleEnabled(module)) {
    return ModuleLockReason.notEnabled;
  }

  // 3. Check if any required dependencies are missing
  final missing = ModuleCatalog.missingDependencies(module, company.enabledModules);
  if (missing.isNotEmpty) {
    return ModuleLockReason.missingDependency;
  }

  return null;
});

/// Indicates whether an [AppModule] is currently active and usable:
/// mode allows AND company enabled AND dependencies satisfied.
final moduleEnabledProvider = Provider.family<bool, AppModule>((ref, module) {
  ref.watch(activeCompanyProvider);
  return ref.watch(moduleLockReasonProvider(module)) == null;
});
