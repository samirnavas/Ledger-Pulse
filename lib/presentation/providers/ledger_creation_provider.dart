import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

const defaultLedgerCreationEnabled = kDebugMode &&
    bool.fromEnvironment('ALLOW_LEDGER_CREATION', defaultValue: true);

final ledgerCreationEnabledProvider =
    NotifierProvider<LedgerCreationNotifier, bool>(LedgerCreationNotifier.new);

class LedgerCreationNotifier extends Notifier<bool> {
  static const _preference = 'development_allow_ledger_creation';

  @override
  bool build() => kDebugMode &&
      (ref.watch(sharedPreferencesProvider)?.getBool(_preference) ??
          defaultLedgerCreationEnabled);

  Future<void> setEnabled(bool enabled) async {
    if (!kDebugMode) return;
    state = enabled;
    await ref.read(sharedPreferencesProvider)?.setBool(_preference, enabled);
  }
}
