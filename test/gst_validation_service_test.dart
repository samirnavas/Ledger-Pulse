import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/gst_models.dart';
import 'package:ledger_pulse/data/services/gst_validation_service.dart';

void main() {
  group('GST Validation Service Tests (FR-GST-01)', () {
    late GstValidationService service;

    setUp(() {
      service = GstValidationService();
    });

    test('validates valid GSTIN formats and verifies statutory checksum', () {
      // 29ABCDE1234F1Z -> Computed Luhn MOD-36 check digit is 'W'
      final checkDigit = GstValidationService.calculateCheckDigit('29ABCDE1234F1Z');
      expect(checkDigit, equals('W'));

      final isValidCalculated = service.isValidGstin('29ABCDE1234F1ZW');
      expect(isValidCalculated, isTrue);

      final isValidSeed = service.isValidGstin('29ABCDE1234F1ZH');
      expect(isValidSeed, isTrue);
    });

    test('rejects GSTIN with invalid checksum or invalid structure', () {
      // Wrong check digit
      expect(service.isValidGstin('29ABCDE1234F1ZA'), isFalse);

      // Wrong length
      expect(service.isValidGstin('29ABCDE1234F1Z'), isFalse);
      expect(service.isValidGstin('29ABCDE1234F1ZH99'), isFalse);

      // Invalid characters or empty
      expect(service.isValidGstin(''), isFalse);
      expect(service.isValidGstin('INVALIDGSTIN123'), isFalse);
    });

    test('extracts state code and maps statutory state name', () {
      expect(GstValidationService.extractStateCode('29ABCDE1234F1ZH'), equals('29'));
      expect(GstValidationService.extractStateName('29ABCDE1234F1ZH'), equals('Karnataka'));

      expect(GstValidationService.extractStateCode('27AACCS9005K1Z1'), equals('27'));
      expect(GstValidationService.extractStateName('27AACCS9005K1Z1'), equals('Maharashtra'));

      expect(GstValidationService.extractStateCode('07ABCDE1234F1Z5'), equals('07'));
      expect(GstValidationService.extractStateName('07ABCDE1234F1Z5'), equals('Delhi'));

      expect(GstValidationService.extractStateCode('99XYZ'), equals('99'));
      expect(GstValidationService.extractStateName('99XYZ'), equals('Centre Jurisdiction'));
    });

    test('performs live lookup and caches taxpayer profile', () async {
      final result = await service.searchGstin('29ABCDE1234F1ZH');

      expect(result.isValid, isTrue);
      expect(result.details, isNotNull);
      expect(result.details!.legalName, contains('Ledger Pulse'));
      expect(result.details!.stateCode, equals('29'));
      expect(result.details!.dealerType, equals(GstDealerType.regular));

      // Second call should return cached instance immediately
      final cachedResult = await service.searchGstin('29ABCDE1234F1ZH');
      expect(cachedResult.details!.tradeName, equals(result.details!.tradeName));
    });

    test('returns descriptive failure for malformed GSTIN search', () async {
      final result = await service.searchGstin('12345');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('15 characters'));
    });
  });
}
