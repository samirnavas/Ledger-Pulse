import 'package:ledger_pulse/core/network/sync_codec.dart';
import 'fake_remote_gateway.dart';

/// Test double extending [FakeGateway] to emulate PostgreSQL timestamptz string normalization.
class StrictFakeRemoteSyncBackend extends FakeGateway {
  static final _tzRegExp = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');
  static const _dateKeys = {
    'date',
    'due_date',
    'start_date',
    'next_run_date',
    'end_date',
    'created_at',
    'updated_at',
  };

  void upsert(String table, String id, Map<String, dynamic> data, {bool isDeleted = false}) {
    final normalizedData = Map<String, dynamic>.from(data);
    normalizedData['id'] = id;
    normalizedData['is_deleted'] = isDeleted;

    for (final entry in data.entries) {
      final key = entry.key;
      final val = entry.value;

      if (_dateKeys.contains(key) && val is String && val.trim().isNotEmpty) {
        final s = val.trim();
        if (!_tzRegExp.hasMatch(s)) {
          normalizedData[key] = encodeTime(DateTime.parse('${s}Z'));
        } else {
          normalizedData[key] = encodeTime(DateTime.parse(s));
        }
      }
    }

    if (!normalizedData.containsKey('updated_at')) {
      normalizedData['updated_at'] = encodeTime(DateTime.now());
    }

    upsertDirect(table, id, normalizedData);
  }

  List<Map<String, dynamic>> getTableRows(String table, {String? companyId}) {
    final tableMap = tables[table];
    if (tableMap == null) return [];
    final list = tableMap.values.toList();
    if (companyId == null) return list;
    return list.where((r) =>
        r['company_id'] == companyId ||
        r['companyId'] == companyId ||
        r['profile_id'] == companyId ||
        r['profileId'] == companyId).toList();
  }
}
