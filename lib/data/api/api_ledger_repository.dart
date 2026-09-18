import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/network/api_config.dart';
import '../../domain/repositories/i_ledger_repository.dart';
import '../models/party_model.dart';
import '../models/transaction_model.dart';

class ApiLedgerRepository implements ILedgerRepository {
  final http.Client _client;
  final StreamController<void> _updateStreamController =
      StreamController<void>.broadcast();

  ApiLedgerRepository({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  Future<http.Response> _executeWithFallback(
    Future<http.Response> Function(String baseUrl) requestFn,
  ) async {
    final candidates = ApiConfig.candidateUrls;
    Object? lastError;

    for (final base in candidates) {
      try {
        final response = await requestFn(base).timeout(
          const Duration(seconds: 4),
        );
        // Successful network handshake - remember this base url
        ApiConfig.setResolvedBaseUrl(base);
        return response;
      } on SocketException catch (e) {
        lastError = e;
        debugPrint('Failed to connect to $base: $e');
        continue;
      } on TimeoutException catch (e) {
        lastError = e;
        debugPrint('Timeout connecting to $base: $e');
        continue;
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint('ClientException connecting to $base: $e');
        continue;
      }
    }

    if (lastError != null) {
      throw Exception(
        'Unable to connect to LedgerPulse server. Please make sure "node server/server.js" is running. (Error: $lastError)',
      );
    }

    throw Exception('Server unreachable');
  }

  @override
  Future<List<Party>> getParties({PartyType? filter}) async {
    final response = await _executeWithFallback((baseUrl) {
      Uri uri = Uri.parse('$baseUrl/api/parties');
      if (filter != null) {
        uri = uri.replace(queryParameters: {'type': filter.name});
      }
      return _client.get(uri, headers: {'Accept': 'application/json'});
    });

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
      return jsonList
          .map((item) => Party.fromMap(item as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception(
        'Failed to load parties (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<Party> getPartyById(String partyId) async {
    final response = await _executeWithFallback((baseUrl) {
      return _client.get(
        Uri.parse('$baseUrl/api/parties/$partyId'),
        headers: {'Accept': 'application/json'},
      );
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonMap =
          jsonDecode(response.body) as Map<String, dynamic>;
      return Party.fromMap(jsonMap);
    } else if (response.statusCode == 404) {
      throw Exception('Party not found with id: $partyId');
    } else {
      throw Exception(
        'Failed to load party (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<void> addParty(Party party) async {
    final response = await _executeWithFallback((baseUrl) {
      return _client.post(
        Uri.parse('$baseUrl/api/parties'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(party.toMap()),
      );
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      _updateStreamController.add(null);
    } else {
      throw Exception(
        'Failed to add party (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<List<LedgerEntry>> getEntriesForParty(String partyId) async {
    final response = await _executeWithFallback((baseUrl) {
      return _client.get(
        Uri.parse('$baseUrl/api/parties/$partyId/entries'),
        headers: {'Accept': 'application/json'},
      );
    });

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
      return jsonList
          .map((item) => LedgerEntry.fromMap(item as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception(
        'Failed to load entries (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<void> addEntry(LedgerEntry entry) async {
    final response = await _executeWithFallback((baseUrl) {
      return _client.post(
        Uri.parse('$baseUrl/api/entries'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(entry.toMap()),
      );
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      _updateStreamController.add(null);
    } else {
      throw Exception(
        'Failed to add entry (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    final response = await _executeWithFallback((baseUrl) {
      return _client.delete(
        Uri.parse('$baseUrl/api/entries/$entryId'),
        headers: {'Accept': 'application/json'},
      );
    });

    if (response.statusCode == 200) {
      _updateStreamController.add(null);
    } else {
      throw Exception(
        'Failed to delete entry (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  Future<(int totalReceivable, int totalPayable)> getBusinessSummary() async {
    final response = await _executeWithFallback((baseUrl) {
      return _client.get(
        Uri.parse('$baseUrl/api/summary'),
        headers: {'Accept': 'application/json'},
      );
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonMap =
          jsonDecode(response.body) as Map<String, dynamic>;
      final int totalReceivable = (jsonMap['totalReceivable'] as num).toInt();
      final int totalPayable = (jsonMap['totalPayable'] as num).toInt();
      return (totalReceivable, totalPayable);
    } else {
      throw Exception(
        'Failed to load business summary (Status: ${response.statusCode}): ${response.body}',
      );
    }
  }

  void dispose() {
    _client.close();
    _updateStreamController.close();
  }
}
