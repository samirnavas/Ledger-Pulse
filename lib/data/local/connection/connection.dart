import 'package:flutter/foundation.dart';

export 'unsupported.dart'
    if (dart.library.js_interop) 'web.dart'
    if (dart.library.io) 'native.dart';

/// Debug builds may open a clean, named database alongside installed data.
/// Changing the namespace leaves all existing databases available for recovery.
String? developmentDatabaseNamespace() {
  if (!kDebugMode) return null;
  const configured = String.fromEnvironment('LEDGERPULSE_DEV_DB_NAMESPACE');
  if (configured.isEmpty) return null;
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(configured)) {
    throw ArgumentError('Invalid Paypr development database namespace.');
  }
  return configured;
}

/// Sanitizes and validates a user identifier for deterministic filesystem path resolution.
/// Ensures consistent database naming across all platforms:
/// - Guest/Default: 'usr_default' -> 'ledger_pulse_usr_default.sqlite'
/// - Authenticated User: 'usr_{uuid}' -> 'ledger_pulse_usr_{uuid}.sqlite'
///
/// Strips illegal filesystem characters and path-traversal sequences.
String sanitizeDatabaseIdentifier(String? uid) {
  if (uid == null || uid.trim().isEmpty || uid == 'usr_default') {
    return 'usr_default';
  }
  final cleaned = uid.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (cleaned.isEmpty || cleaned == 'default') {
    return 'usr_default';
  }
  return cleaned.startsWith('usr_') ? cleaned : 'usr_$cleaned';
}
