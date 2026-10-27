import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/company_model.dart';

void main() {
  group('Company Model Tests', () {
    final baseTime = DateTime(2025, 1, 1, 10, 0, 0);
    final baseCompany = Company(
      id: 'cmp_1',
      name: 'Alpha Traders',
      legalName: 'Alpha Traders Pvt Ltd',
      gstin: '29ABCDE1234F1Z5',
      stateCode: '29',
      dealerType: 'regular',
      currencyCode: 'INR',
      address: '123 Market Road, Bangalore',
      email: 'alpha@example.com',
      phoneNumber: '+91 98765 00000',
      logoUrl: 'https://example.com/logo.png',
      signatureUrl: 'https://example.com/sig.png',
      signatoryName: 'John Doe',
      bankName: 'HDFC Bank',
      bankAccountNumber: '123456789012',
      bankIfsc: 'HDFC0001234',
      upiId: 'alpha@okaxis',
      isCloudSyncEnabled: true,
      isDropboxSyncEnabled: false,
      isActive: true,
      createdAt: baseTime,
      updatedAt: baseTime,
    );

    test('Company equality and hashCode are identical for identical values', () {
      final duplicate = Company(
        id: 'cmp_1',
        name: 'Alpha Traders',
        legalName: 'Alpha Traders Pvt Ltd',
        gstin: '29ABCDE1234F1Z5',
        stateCode: '29',
        dealerType: 'regular',
        currencyCode: 'INR',
        address: '123 Market Road, Bangalore',
        email: 'alpha@example.com',
        phoneNumber: '+91 98765 00000',
        logoUrl: 'https://example.com/logo.png',
        signatureUrl: 'https://example.com/sig.png',
        signatoryName: 'John Doe',
        bankName: 'HDFC Bank',
        bankAccountNumber: '123456789012',
        bankIfsc: 'HDFC0001234',
        upiId: 'alpha@okaxis',
        isCloudSyncEnabled: true,
        isDropboxSyncEnabled: false,
        isActive: true,
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      expect(baseCompany == duplicate, isTrue);
      expect(baseCompany.hashCode, equals(duplicate.hashCode));
    });

    test('Company equality changes when any field changes', () {
      final variations = <Company>[
        baseCompany.copyWith(id: 'cmp_2'),
        baseCompany.copyWith(name: 'Beta Traders'),
        baseCompany.copyWith(legalName: 'Beta Traders Pvt Ltd'),
        baseCompany.copyWith(gstin: '29ZZZDE1234F1Z5'),
        baseCompany.copyWith(stateCode: '27'),
        baseCompany.copyWith(dealerType: 'composition'),
        baseCompany.copyWith(currencyCode: 'USD'),
        baseCompany.copyWith(address: '456 New Road, Mumbai'),
        baseCompany.copyWith(email: 'beta@example.com'),
        baseCompany.copyWith(phoneNumber: '+91 91234 56789'),
        baseCompany.copyWith(logoUrl: 'https://example.com/other.png'),
        baseCompany.copyWith(signatureUrl: 'https://example.com/othersig.png'),
        baseCompany.copyWith(signatoryName: 'Jane Smith'),
        baseCompany.copyWith(bankName: 'ICICI Bank'),
        baseCompany.copyWith(bankAccountNumber: '987654321098'),
        baseCompany.copyWith(bankIfsc: 'ICIC0005678'),
        baseCompany.copyWith(upiId: 'beta@icici'),
        baseCompany.copyWith(isCloudSyncEnabled: false),
        baseCompany.copyWith(isDropboxSyncEnabled: true),
        baseCompany.copyWith(isActive: false),
        baseCompany.copyWith(createdAt: baseTime.add(const Duration(days: 1))),
        baseCompany.copyWith(updatedAt: baseTime.add(const Duration(hours: 2))),
      ];

      for (var i = 0; i < variations.length; i++) {
        final variant = variations[i];
        expect(baseCompany == variant, isFalse,
            reason: 'Variant $i should not equal baseCompany');
        expect(baseCompany.hashCode == variant.hashCode, isFalse,
            reason: 'Variant $i hashCode should not equal baseCompany hashCode');
      }
    });

    test('Company map round trip preserves all fields', () {
      final map = baseCompany.toMap();
      final roundTrip = Company.fromMap(map);

      expect(roundTrip, equals(baseCompany));
      expect(roundTrip.id, equals('cmp_1'));
      expect(roundTrip.name, equals('Alpha Traders'));
      expect(roundTrip.legalName, equals('Alpha Traders Pvt Ltd'));
      expect(roundTrip.gstin, equals('29ABCDE1234F1Z5'));
      expect(roundTrip.stateCode, equals('29'));
      expect(roundTrip.dealerType, equals('regular'));
      expect(roundTrip.currencyCode, equals('INR'));
      expect(roundTrip.address, equals('123 Market Road, Bangalore'));
      expect(roundTrip.email, equals('alpha@example.com'));
      expect(roundTrip.phoneNumber, equals('+91 98765 00000'));
      expect(roundTrip.logoUrl, equals('https://example.com/logo.png'));
      expect(roundTrip.signatureUrl, equals('https://example.com/sig.png'));
      expect(roundTrip.signatoryName, equals('John Doe'));
      expect(roundTrip.bankName, equals('HDFC Bank'));
      expect(roundTrip.bankAccountNumber, equals('123456789012'));
      expect(roundTrip.bankIfsc, equals('HDFC0001234'));
      expect(roundTrip.upiId, equals('alpha@okaxis'));
      expect(roundTrip.isCloudSyncEnabled, isTrue);
      expect(roundTrip.isDropboxSyncEnabled, isFalse);
      expect(roundTrip.isActive, isTrue);
      expect(roundTrip.createdAt, equals(baseTime));
      expect(roundTrip.updatedAt, equals(baseTime));
    });
  });
}
