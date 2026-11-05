/// Encodes a [DateTime] into a UTC ISO-8601 string for sync outbox and remote PostgREST APIs.
String encodeTime(DateTime dt) {
  return dt.toUtc().toIso8601String();
}

/// Decodes an ISO-8601 string into a local [DateTime].
/// Strings lacking a timezone offset (e.g. "2026-11-04T10:00:00.000") are treated as UTC.
DateTime decodeTime(dynamic value) {
  if (value == null) {
    return DateTime.now();
  }
  if (value is DateTime) {
    return value.toLocal();
  }
  final s = value.toString().trim();
  if (s.isEmpty) {
    return DateTime.now();
  }
  final hasOffset = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  final isoStr = hasOffset ? s : '${s}Z';
  return DateTime.parse(isoStr).toLocal();
}
