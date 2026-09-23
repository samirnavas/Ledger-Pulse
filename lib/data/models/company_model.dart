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
  final DateTime createdAt;
  final DateTime updatedAt;

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
    required this.createdAt,
    required this.updatedAt,
  });

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
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'legalName': legalName,
      'gstin': gstin,
      'stateCode': stateCode,
      'dealerType': dealerType,
      'currencyCode': currencyCode,
      'address': address,
      'email': email,
      'phoneNumber': phoneNumber,
      'logoUrl': logoUrl,
      'signatureUrl': signatureUrl,
      'signatoryName': signatoryName,
      'bankName': bankName,
      'bankAccountNumber': bankAccountNumber,
      'bankIfsc': bankIfsc,
      'upiId': upiId,
      'isCloudSyncEnabled': isCloudSyncEnabled ? 1 : 0,
      'isDropboxSyncEnabled': isDropboxSyncEnabled ? 1 : 0,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Company.fromMap(Map<String, dynamic> map) {
    return Company(
      id: map['id'] as String,
      name: map['name'] as String,
      legalName: (map['legalName'] ?? map['name']) as String,
      gstin: map['gstin'] as String?,
      stateCode: map['stateCode'] as String?,
      dealerType: (map['dealerType'] as String?) ?? 'regular',
      currencyCode: (map['currencyCode'] ?? 'INR') as String,
      address: map['address'] as String?,
      email: map['email'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      logoUrl: map['logoUrl'] as String?,
      signatureUrl: map['signatureUrl'] as String?,
      signatoryName: map['signatoryName'] as String?,
      bankName: map['bankName'] as String?,
      bankAccountNumber: map['bankAccountNumber'] as String?,
      bankIfsc: map['bankIfsc'] as String?,
      upiId: map['upiId'] as String?,
      isCloudSyncEnabled: map['isCloudSyncEnabled'] == 1 || map['isCloudSyncEnabled'] == true,
      isDropboxSyncEnabled: map['isDropboxSyncEnabled'] == 1 || map['isDropboxSyncEnabled'] == true,
      isActive: map['isActive'] == null || map['isActive'] == 1 || map['isActive'] == true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
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
        other.currencyCode == currencyCode &&
        other.isCloudSyncEnabled == isCloudSyncEnabled &&
        other.isDropboxSyncEnabled == isDropboxSyncEnabled &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        legalName,
        gstin,
        currencyCode,
        isCloudSyncEnabled,
        isDropboxSyncEnabled,
        isActive,
      );
}
