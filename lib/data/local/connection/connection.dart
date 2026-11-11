export 'unsupported.dart'
    if (dart.library.js_interop) 'web.dart'
    if (dart.library.io) 'native.dart';

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
