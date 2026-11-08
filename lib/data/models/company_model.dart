import 'dart:convert';
import '../../core/network/sync_codec.dart';
import 'company_mode.dart';

export 'company_mode.dart';

class Company {
  final String id;
  final String name;
  final String legalName;
  final String? gstin;
  final String? stateCode;
  final String dealerType; // regular, composition
  final String currencyCode;
  final String? address;
  final String? email;
  final String? phoneNumber;
  final String? logoUrl;
  final String? signatureUrl;
  final String? signatoryName;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? upiId;
  final bool isCloudSyncEnabled;
  final bool isDropboxSyncEnabled;
  final bool isActive;
  final CompanyMode mode;
  final Set<AppModule> enabledModules;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? ownerId;

  const Company({
    required this.id,
    required this.name,
    required this.legalName,
    this.gstin,
    this.stateCode,
    this.dealerType = 'regular',
    this.currencyCode = 'INR',
    this.address,
    this.email,
    this.phoneNumber,
    this.logoUrl,
    this.signatureUrl,
    this.signatoryName,
    this.bankName,
    this.bankAccountNumber,
    this.bankIfsc,
    this.upiId,
    this.isCloudSyncEnabled = true,
    this.isDropboxSyncEnabled = false,
    this.isActive = true,
    this.mode = CompanyMode.ledger,
    this.enabledModules = AppModule.allModules,
    required this.createdAt,
    required this.updatedAt,
    this.ownerId,
  });

  bool isModuleEnabled(AppModule module) => enabledModules.contains(module);
  bool get isExpense => mode == CompanyMode.expenseTracker;
  bool get isLedger => mode == CompanyMode.ledger;

  Company copyWith({
    String? id,
    String? name,
    String? legalName,
    String? gstin,
    String? stateCode,
    String? dealerType,
    String? currencyCode,
    String? address,
    String? email,
    String? phoneNumber,
    String? logoUrl,
    String? signatureUrl,
    String? signatoryName,
    String? bankName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? upiId,
    bool? isCloudSyncEnabled,
    bool? isDropboxSyncEnabled,
    bool? isActive,
    CompanyMode? mode,
    Set<AppModule>? enabledModules,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ownerId,
  }) {
    if (mode != null && mode != this.mode) {
      throw StateError(
        'Profile type is immutable after creation. Cannot change from "${this.mode.canonicalValue}" to "${mode.canonicalValue}".',
      );
    }
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      gstin: gstin ?? this.gstin,
      stateCode: stateCode ?? this.stateCode,
      dealerType: dealerType ?? this.dealerType,
      currencyCode: currencyCode ?? this.currencyCode,
      address: address ?? this.address,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      logoUrl: logoUrl ?? this.logoUrl,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      signatoryName: signatoryName ?? this.signatoryName,
      bankName: bankName ?? this.bankName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankIfsc: bankIfsc ?? this.bankIfsc,
      upiId: upiId ?? this.upiId,
      isCloudSyncEnabled: isCloudSyncEnabled ?? this.isCloudSyncEnabled,
      isDropboxSyncEnabled: isDropboxSyncEnabled ?? this.isDropboxSyncEnabled,
      isActive: isActive ?? this.isActive,
      mode: mode ?? this.mode,
      enabledModules: enabledModules ?? this.enabledModules,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  Map<String, dynamic> toMap() {
    final modulesJson = jsonEncode(enabledModules.map((m) => m.name).toList());
    return {
      'id': id,
      'name': name,
      'legalName': legalName,
      'legal_name': legalName,
      'gstin': gstin,
      'stateCode': stateCode,
      'state_code': stateCode,
      'dealerType': dealerType,
      'dealer_type': dealerType,
      'currencyCode': currencyCode,
      'currency_code': currencyCode,
      'address': address,
      'email': email,
      'phoneNumber': phoneNumber,
      'phone_number': phoneNumber,
      'logoUrl': logoUrl,
      'logo_url': logoUrl,
      'signatureUrl': signatureUrl,
      'signature_url': signatureUrl,
      'signatoryName': signatoryName,
      'signatory_name': signatoryName,
      'bankName': bankName,
      'bank_name': bankName,
      'bankAccountNumber': bankAccountNumber,
      'bank_account_number': bankAccountNumber,
      'bankIfsc': bankIfsc,
      'bank_ifsc': bankIfsc,
      'upiId': upiId,
      'upi_id': upiId,
      'isCloudSyncEnabled': isCloudSyncEnabled ? 1 : 0,
      'is_cloud_sync_enabled': isCloudSyncEnabled,
      'isDropboxSyncEnabled': isDropboxSyncEnabled ? 1 : 0,
      'is_dropbox_sync_enabled': isDropboxSyncEnabled,
      'isActive': isActive ? 1 : 0,
      'is_active': isActive,
      'mode': mode.canonicalValue,
      'enabledModules': modulesJson,
      'enabledModulesJson': modulesJson,
      'enabled_modules': modulesJson,
      'createdAt': encodeTime(createdAt),
      'created_at': encodeTime(createdAt),
      'updatedAt': encodeTime(updatedAt),
      'updated_at': encodeTime(updatedAt),
      'ownerId': ownerId,
      'owner_id': ownerId,
    };
  }

  factory Company.fromMap(Map<String, dynamic> map) {
    return Company(
      id: map['id'] as String,
      name: map['name'] as String,
      legalName: (map['legalName'] ?? map['legal_name'] ?? map['name']) as String,
      gstin: map['gstin'] as String?,
      stateCode: (map['stateCode'] ?? map['state_code']) as String?,
      dealerType: (map['dealerType'] ?? map['dealer_type'] as String?) ?? 'regular',
      currencyCode: (map['currencyCode'] ?? map['currency_code'] ?? 'INR') as String,
      address: map['address'] as String?,
      email: map['email'] as String?,
      phoneNumber: (map['phoneNumber'] ?? map['phone_number']) as String?,
      logoUrl: (map['logoUrl'] ?? map['logo_url']) as String?,
      signatureUrl: (map['signatureUrl'] ?? map['signature_url']) as String?,
      signatoryName: (map['signatoryName'] ?? map['signatory_name']) as String?,
      bankName: (map['bankName'] ?? map['bank_name']) as String?,
      bankAccountNumber: (map['bankAccountNumber'] ?? map['bank_account_number']) as String?,
      bankIfsc: (map['bankIfsc'] ?? map['bank_ifsc']) as String?,
      upiId: (map['upiId'] ?? map['upi_id']) as String?,
      isCloudSyncEnabled: map['isCloudSyncEnabled'] == 1 || map['isCloudSyncEnabled'] == true || map['is_cloud_sync_enabled'] == true,
      isDropboxSyncEnabled: map['isDropboxSyncEnabled'] == 1 || map['isDropboxSyncEnabled'] == true || map['is_dropbox_sync_enabled'] == true,
      isActive: map['isActive'] == null || map['isActive'] == 1 || map['isActive'] == true || map['is_active'] == true,
      mode: map.containsKey('mode') && map['mode'] != null
          ? CompanyMode.fromName(map['mode']?.toString())
          : (map.containsKey('mode')
              ? throw const UnknownProfileTypeException(null)
              : CompanyMode.ledger),
      enabledModules: AppModule.parseSet(
        map['enabled_modules'] ?? map['enabledModules'] ?? map['enabledModulesJson'] ?? map['enabled_modules_json'],
      ),
      createdAt: decodeTime(map['createdAt'] ?? map['created_at']),
      updatedAt: decodeTime(map['updatedAt'] ?? map['updated_at']),
      ownerId: (map['ownerId'] ?? map['owner_id']) as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Company &&
        other.id == id &&
        other.name == name &&
        other.legalName == legalName &&
        other.gstin == gstin &&
        other.stateCode == stateCode &&
        other.dealerType == dealerType &&
        other.currencyCode == currencyCode &&
        other.address == address &&
        other.email == email &&
        other.phoneNumber == phoneNumber &&
        other.logoUrl == logoUrl &&
        other.signatureUrl == signatureUrl &&
        other.signatoryName == signatoryName &&
        other.bankName == bankName &&
        other.bankAccountNumber == bankAccountNumber &&
        other.bankIfsc == bankIfsc &&
        other.upiId == upiId &&
        other.isCloudSyncEnabled == isCloudSyncEnabled &&
        other.isDropboxSyncEnabled == isDropboxSyncEnabled &&
        other.isActive == isActive &&
        other.mode == mode &&
        other.enabledModules.length == enabledModules.length &&
        other.enabledModules.containsAll(enabledModules) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.ownerId == ownerId;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        legalName,
        gstin,
        stateCode,
        dealerType,
        currencyCode,
        address,
        email,
        phoneNumber,
        logoUrl,
        signatureUrl,
        signatoryName,
        bankName,
        bankAccountNumber,
        bankIfsc,
        upiId,
        isCloudSyncEnabled,
        isDropboxSyncEnabled,
        isActive,
        mode,
        Object.hashAllUnordered(enabledModules),
        createdAt,
        updatedAt,
        ownerId,
      ]);
}
