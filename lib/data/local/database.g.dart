// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CompaniesTable extends Companies
    with TableInfo<$CompaniesTable, CompanyTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CompaniesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _legalNameMeta = const VerificationMeta(
    'legalName',
  );
  @override
  late final GeneratedColumn<String> legalName = GeneratedColumn<String>(
    'legal_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gstinMeta = const VerificationMeta('gstin');
  @override
  late final GeneratedColumn<String> gstin = GeneratedColumn<String>(
    'gstin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyCodeMeta = const VerificationMeta(
    'currencyCode',
  );
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
    'currency_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('INR'),
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneNumberMeta = const VerificationMeta(
    'phoneNumber',
  );
  @override
  late final GeneratedColumn<String> phoneNumber = GeneratedColumn<String>(
    'phone_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isCloudSyncEnabledMeta =
      const VerificationMeta('isCloudSyncEnabled');
  @override
  late final GeneratedColumn<bool> isCloudSyncEnabled = GeneratedColumn<bool>(
    'is_cloud_sync_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_cloud_sync_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isDropboxSyncEnabledMeta =
      const VerificationMeta('isDropboxSyncEnabled');
  @override
  late final GeneratedColumn<bool> isDropboxSyncEnabled = GeneratedColumn<bool>(
    'is_dropbox_sync_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dropbox_sync_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    legalName,
    gstin,
    currencyCode,
    address,
    email,
    phoneNumber,
    isCloudSyncEnabled,
    isDropboxSyncEnabled,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'companies';
  @override
  VerificationContext validateIntegrity(
    Insertable<CompanyTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('legal_name')) {
      context.handle(
        _legalNameMeta,
        legalName.isAcceptableOrUnknown(data['legal_name']!, _legalNameMeta),
      );
    } else if (isInserting) {
      context.missing(_legalNameMeta);
    }
    if (data.containsKey('gstin')) {
      context.handle(
        _gstinMeta,
        gstin.isAcceptableOrUnknown(data['gstin']!, _gstinMeta),
      );
    }
    if (data.containsKey('currency_code')) {
      context.handle(
        _currencyCodeMeta,
        currencyCode.isAcceptableOrUnknown(
          data['currency_code']!,
          _currencyCodeMeta,
        ),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('phone_number')) {
      context.handle(
        _phoneNumberMeta,
        phoneNumber.isAcceptableOrUnknown(
          data['phone_number']!,
          _phoneNumberMeta,
        ),
      );
    }
    if (data.containsKey('is_cloud_sync_enabled')) {
      context.handle(
        _isCloudSyncEnabledMeta,
        isCloudSyncEnabled.isAcceptableOrUnknown(
          data['is_cloud_sync_enabled']!,
          _isCloudSyncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('is_dropbox_sync_enabled')) {
      context.handle(
        _isDropboxSyncEnabledMeta,
        isDropboxSyncEnabled.isAcceptableOrUnknown(
          data['is_dropbox_sync_enabled']!,
          _isDropboxSyncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CompanyTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CompanyTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      legalName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legal_name'],
      )!,
      gstin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gstin'],
      ),
      currencyCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_code'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      phoneNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_number'],
      ),
      isCloudSyncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_cloud_sync_enabled'],
      )!,
      isDropboxSyncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dropbox_sync_enabled'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CompaniesTable createAlias(String alias) {
    return $CompaniesTable(attachedDatabase, alias);
  }
}

class CompanyTableData extends DataClass
    implements Insertable<CompanyTableData> {
  final String id;
  final String name;
  final String legalName;
  final String? gstin;
  final String currencyCode;
  final String? address;
  final String? email;
  final String? phoneNumber;
  final bool isCloudSyncEnabled;
  final bool isDropboxSyncEnabled;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CompanyTableData({
    required this.id,
    required this.name,
    required this.legalName,
    this.gstin,
    required this.currencyCode,
    this.address,
    this.email,
    this.phoneNumber,
    required this.isCloudSyncEnabled,
    required this.isDropboxSyncEnabled,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['legal_name'] = Variable<String>(legalName);
    if (!nullToAbsent || gstin != null) {
      map['gstin'] = Variable<String>(gstin);
    }
    map['currency_code'] = Variable<String>(currencyCode);
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    if (!nullToAbsent || phoneNumber != null) {
      map['phone_number'] = Variable<String>(phoneNumber);
    }
    map['is_cloud_sync_enabled'] = Variable<bool>(isCloudSyncEnabled);
    map['is_dropbox_sync_enabled'] = Variable<bool>(isDropboxSyncEnabled);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CompaniesCompanion toCompanion(bool nullToAbsent) {
    return CompaniesCompanion(
      id: Value(id),
      name: Value(name),
      legalName: Value(legalName),
      gstin: gstin == null && nullToAbsent
          ? const Value.absent()
          : Value(gstin),
      currencyCode: Value(currencyCode),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      phoneNumber: phoneNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(phoneNumber),
      isCloudSyncEnabled: Value(isCloudSyncEnabled),
      isDropboxSyncEnabled: Value(isDropboxSyncEnabled),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CompanyTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CompanyTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      legalName: serializer.fromJson<String>(json['legalName']),
      gstin: serializer.fromJson<String?>(json['gstin']),
      currencyCode: serializer.fromJson<String>(json['currencyCode']),
      address: serializer.fromJson<String?>(json['address']),
      email: serializer.fromJson<String?>(json['email']),
      phoneNumber: serializer.fromJson<String?>(json['phoneNumber']),
      isCloudSyncEnabled: serializer.fromJson<bool>(json['isCloudSyncEnabled']),
      isDropboxSyncEnabled: serializer.fromJson<bool>(
        json['isDropboxSyncEnabled'],
      ),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'legalName': serializer.toJson<String>(legalName),
      'gstin': serializer.toJson<String?>(gstin),
      'currencyCode': serializer.toJson<String>(currencyCode),
      'address': serializer.toJson<String?>(address),
      'email': serializer.toJson<String?>(email),
      'phoneNumber': serializer.toJson<String?>(phoneNumber),
      'isCloudSyncEnabled': serializer.toJson<bool>(isCloudSyncEnabled),
      'isDropboxSyncEnabled': serializer.toJson<bool>(isDropboxSyncEnabled),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CompanyTableData copyWith({
    String? id,
    String? name,
    String? legalName,
    Value<String?> gstin = const Value.absent(),
    String? currencyCode,
    Value<String?> address = const Value.absent(),
    Value<String?> email = const Value.absent(),
    Value<String?> phoneNumber = const Value.absent(),
    bool? isCloudSyncEnabled,
    bool? isDropboxSyncEnabled,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CompanyTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    legalName: legalName ?? this.legalName,
    gstin: gstin.present ? gstin.value : this.gstin,
    currencyCode: currencyCode ?? this.currencyCode,
    address: address.present ? address.value : this.address,
    email: email.present ? email.value : this.email,
    phoneNumber: phoneNumber.present ? phoneNumber.value : this.phoneNumber,
    isCloudSyncEnabled: isCloudSyncEnabled ?? this.isCloudSyncEnabled,
    isDropboxSyncEnabled: isDropboxSyncEnabled ?? this.isDropboxSyncEnabled,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CompanyTableData copyWithCompanion(CompaniesCompanion data) {
    return CompanyTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      legalName: data.legalName.present ? data.legalName.value : this.legalName,
      gstin: data.gstin.present ? data.gstin.value : this.gstin,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      address: data.address.present ? data.address.value : this.address,
      email: data.email.present ? data.email.value : this.email,
      phoneNumber: data.phoneNumber.present
          ? data.phoneNumber.value
          : this.phoneNumber,
      isCloudSyncEnabled: data.isCloudSyncEnabled.present
          ? data.isCloudSyncEnabled.value
          : this.isCloudSyncEnabled,
      isDropboxSyncEnabled: data.isDropboxSyncEnabled.present
          ? data.isDropboxSyncEnabled.value
          : this.isDropboxSyncEnabled,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CompanyTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('legalName: $legalName, ')
          ..write('gstin: $gstin, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('address: $address, ')
          ..write('email: $email, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('isCloudSyncEnabled: $isCloudSyncEnabled, ')
          ..write('isDropboxSyncEnabled: $isDropboxSyncEnabled, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    legalName,
    gstin,
    currencyCode,
    address,
    email,
    phoneNumber,
    isCloudSyncEnabled,
    isDropboxSyncEnabled,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompanyTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.legalName == this.legalName &&
          other.gstin == this.gstin &&
          other.currencyCode == this.currencyCode &&
          other.address == this.address &&
          other.email == this.email &&
          other.phoneNumber == this.phoneNumber &&
          other.isCloudSyncEnabled == this.isCloudSyncEnabled &&
          other.isDropboxSyncEnabled == this.isDropboxSyncEnabled &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CompaniesCompanion extends UpdateCompanion<CompanyTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> legalName;
  final Value<String?> gstin;
  final Value<String> currencyCode;
  final Value<String?> address;
  final Value<String?> email;
  final Value<String?> phoneNumber;
  final Value<bool> isCloudSyncEnabled;
  final Value<bool> isDropboxSyncEnabled;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CompaniesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.legalName = const Value.absent(),
    this.gstin = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.address = const Value.absent(),
    this.email = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.isCloudSyncEnabled = const Value.absent(),
    this.isDropboxSyncEnabled = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CompaniesCompanion.insert({
    required String id,
    required String name,
    required String legalName,
    this.gstin = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.address = const Value.absent(),
    this.email = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.isCloudSyncEnabled = const Value.absent(),
    this.isDropboxSyncEnabled = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       legalName = Value(legalName);
  static Insertable<CompanyTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? legalName,
    Expression<String>? gstin,
    Expression<String>? currencyCode,
    Expression<String>? address,
    Expression<String>? email,
    Expression<String>? phoneNumber,
    Expression<bool>? isCloudSyncEnabled,
    Expression<bool>? isDropboxSyncEnabled,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (legalName != null) 'legal_name': legalName,
      if (gstin != null) 'gstin': gstin,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (address != null) 'address': address,
      if (email != null) 'email': email,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (isCloudSyncEnabled != null)
        'is_cloud_sync_enabled': isCloudSyncEnabled,
      if (isDropboxSyncEnabled != null)
        'is_dropbox_sync_enabled': isDropboxSyncEnabled,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CompaniesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? legalName,
    Value<String?>? gstin,
    Value<String>? currencyCode,
    Value<String?>? address,
    Value<String?>? email,
    Value<String?>? phoneNumber,
    Value<bool>? isCloudSyncEnabled,
    Value<bool>? isDropboxSyncEnabled,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CompaniesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      gstin: gstin ?? this.gstin,
      currencyCode: currencyCode ?? this.currencyCode,
      address: address ?? this.address,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isCloudSyncEnabled: isCloudSyncEnabled ?? this.isCloudSyncEnabled,
      isDropboxSyncEnabled: isDropboxSyncEnabled ?? this.isDropboxSyncEnabled,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (legalName.present) {
      map['legal_name'] = Variable<String>(legalName.value);
    }
    if (gstin.present) {
      map['gstin'] = Variable<String>(gstin.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phoneNumber.present) {
      map['phone_number'] = Variable<String>(phoneNumber.value);
    }
    if (isCloudSyncEnabled.present) {
      map['is_cloud_sync_enabled'] = Variable<bool>(isCloudSyncEnabled.value);
    }
    if (isDropboxSyncEnabled.present) {
      map['is_dropbox_sync_enabled'] = Variable<bool>(
        isDropboxSyncEnabled.value,
      );
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CompaniesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('legalName: $legalName, ')
          ..write('gstin: $gstin, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('address: $address, ')
          ..write('email: $email, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('isCloudSyncEnabled: $isCloudSyncEnabled, ')
          ..write('isDropboxSyncEnabled: $isDropboxSyncEnabled, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PartiesTable extends Parties
    with TableInfo<$PartiesTable, PartyTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PartiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cmp_default'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneNumberMeta = const VerificationMeta(
    'phoneNumber',
  );
  @override
  late final GeneratedColumn<String> phoneNumber = GeneratedColumn<String>(
    'phone_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<PartyType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<PartyType>($PartiesTable.$convertertype);
  static const VerificationMeta _netBalanceInCentsMeta = const VerificationMeta(
    'netBalanceInCents',
  );
  @override
  late final GeneratedColumn<int> netBalanceInCents = GeneratedColumn<int>(
    'net_balance_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
    'last_updated',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta(
    'isDeleted',
  );
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    name,
    phoneNumber,
    type,
    netBalanceInCents,
    lastUpdated,
    isDeleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'parties';
  @override
  VerificationContext validateIntegrity(
    Insertable<PartyTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone_number')) {
      context.handle(
        _phoneNumberMeta,
        phoneNumber.isAcceptableOrUnknown(
          data['phone_number']!,
          _phoneNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_phoneNumberMeta);
    }
    if (data.containsKey('net_balance_in_cents')) {
      context.handle(
        _netBalanceInCentsMeta,
        netBalanceInCents.isAcceptableOrUnknown(
          data['net_balance_in_cents']!,
          _netBalanceInCentsMeta,
        ),
      );
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUpdatedMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PartyTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PartyTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phoneNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_number'],
      )!,
      type: $PartiesTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      netBalanceInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}net_balance_in_cents'],
      )!,
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_updated'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
    );
  }

  @override
  $PartiesTable createAlias(String alias) {
    return $PartiesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<PartyType, String, String> $convertertype =
      const EnumNameConverter<PartyType>(PartyType.values);
}

class PartyTableData extends DataClass implements Insertable<PartyTableData> {
  final String id;
  final String companyId;
  final String name;
  final String phoneNumber;
  final PartyType type;
  final int netBalanceInCents;
  final DateTime lastUpdated;
  final bool isDeleted;
  const PartyTableData({
    required this.id,
    required this.companyId,
    required this.name,
    required this.phoneNumber,
    required this.type,
    required this.netBalanceInCents,
    required this.lastUpdated,
    required this.isDeleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['name'] = Variable<String>(name);
    map['phone_number'] = Variable<String>(phoneNumber);
    {
      map['type'] = Variable<String>($PartiesTable.$convertertype.toSql(type));
    }
    map['net_balance_in_cents'] = Variable<int>(netBalanceInCents);
    map['last_updated'] = Variable<DateTime>(lastUpdated);
    map['is_deleted'] = Variable<bool>(isDeleted);
    return map;
  }

  PartiesCompanion toCompanion(bool nullToAbsent) {
    return PartiesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      name: Value(name),
      phoneNumber: Value(phoneNumber),
      type: Value(type),
      netBalanceInCents: Value(netBalanceInCents),
      lastUpdated: Value(lastUpdated),
      isDeleted: Value(isDeleted),
    );
  }

  factory PartyTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PartyTableData(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      name: serializer.fromJson<String>(json['name']),
      phoneNumber: serializer.fromJson<String>(json['phoneNumber']),
      type: $PartiesTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      netBalanceInCents: serializer.fromJson<int>(json['netBalanceInCents']),
      lastUpdated: serializer.fromJson<DateTime>(json['lastUpdated']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'name': serializer.toJson<String>(name),
      'phoneNumber': serializer.toJson<String>(phoneNumber),
      'type': serializer.toJson<String>(
        $PartiesTable.$convertertype.toJson(type),
      ),
      'netBalanceInCents': serializer.toJson<int>(netBalanceInCents),
      'lastUpdated': serializer.toJson<DateTime>(lastUpdated),
      'isDeleted': serializer.toJson<bool>(isDeleted),
    };
  }

  PartyTableData copyWith({
    String? id,
    String? companyId,
    String? name,
    String? phoneNumber,
    PartyType? type,
    int? netBalanceInCents,
    DateTime? lastUpdated,
    bool? isDeleted,
  }) => PartyTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    name: name ?? this.name,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    type: type ?? this.type,
    netBalanceInCents: netBalanceInCents ?? this.netBalanceInCents,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    isDeleted: isDeleted ?? this.isDeleted,
  );
  PartyTableData copyWithCompanion(PartiesCompanion data) {
    return PartyTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      name: data.name.present ? data.name.value : this.name,
      phoneNumber: data.phoneNumber.present
          ? data.phoneNumber.value
          : this.phoneNumber,
      type: data.type.present ? data.type.value : this.type,
      netBalanceInCents: data.netBalanceInCents.present
          ? data.netBalanceInCents.value
          : this.netBalanceInCents,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PartyTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('name: $name, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('type: $type, ')
          ..write('netBalanceInCents: $netBalanceInCents, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    name,
    phoneNumber,
    type,
    netBalanceInCents,
    lastUpdated,
    isDeleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PartyTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.name == this.name &&
          other.phoneNumber == this.phoneNumber &&
          other.type == this.type &&
          other.netBalanceInCents == this.netBalanceInCents &&
          other.lastUpdated == this.lastUpdated &&
          other.isDeleted == this.isDeleted);
}

class PartiesCompanion extends UpdateCompanion<PartyTableData> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> name;
  final Value<String> phoneNumber;
  final Value<PartyType> type;
  final Value<int> netBalanceInCents;
  final Value<DateTime> lastUpdated;
  final Value<bool> isDeleted;
  final Value<int> rowid;
  const PartiesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.name = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.type = const Value.absent(),
    this.netBalanceInCents = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PartiesCompanion.insert({
    required String id,
    this.companyId = const Value.absent(),
    required String name,
    required String phoneNumber,
    required PartyType type,
    this.netBalanceInCents = const Value.absent(),
    required DateTime lastUpdated,
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       phoneNumber = Value(phoneNumber),
       type = Value(type),
       lastUpdated = Value(lastUpdated);
  static Insertable<PartyTableData> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? name,
    Expression<String>? phoneNumber,
    Expression<String>? type,
    Expression<int>? netBalanceInCents,
    Expression<DateTime>? lastUpdated,
    Expression<bool>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (name != null) 'name': name,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (type != null) 'type': type,
      if (netBalanceInCents != null) 'net_balance_in_cents': netBalanceInCents,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PartiesCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? name,
    Value<String>? phoneNumber,
    Value<PartyType>? type,
    Value<int>? netBalanceInCents,
    Value<DateTime>? lastUpdated,
    Value<bool>? isDeleted,
    Value<int>? rowid,
  }) {
    return PartiesCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      type: type ?? this.type,
      netBalanceInCents: netBalanceInCents ?? this.netBalanceInCents,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phoneNumber.present) {
      map['phone_number'] = Variable<String>(phoneNumber.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $PartiesTable.$convertertype.toSql(type.value),
      );
    }
    if (netBalanceInCents.present) {
      map['net_balance_in_cents'] = Variable<int>(netBalanceInCents.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PartiesCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('name: $name, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('type: $type, ')
          ..write('netBalanceInCents: $netBalanceInCents, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LedgerEntriesTable extends LedgerEntries
    with TableInfo<$LedgerEntriesTable, LedgerEntryTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cmp_default'),
  );
  static const VerificationMeta _partyIdMeta = const VerificationMeta(
    'partyId',
  );
  @override
  late final GeneratedColumn<String> partyId = GeneratedColumn<String>(
    'party_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES parties (id)',
    ),
  );
  static const VerificationMeta _amountInCentsMeta = const VerificationMeta(
    'amountInCents',
  );
  @override
  late final GeneratedColumn<int> amountInCents = GeneratedColumn<int>(
    'amount_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<EntryType, String> type =
      GeneratedColumn<String>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EntryType>($LedgerEntriesTable.$convertertype);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptPhotoUrlMeta = const VerificationMeta(
    'receiptPhotoUrl',
  );
  @override
  late final GeneratedColumn<String> receiptPhotoUrl = GeneratedColumn<String>(
    'receipt_photo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isVoidedMeta = const VerificationMeta(
    'isVoided',
  );
  @override
  late final GeneratedColumn<bool> isVoided = GeneratedColumn<bool>(
    'is_voided',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_voided" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    partyId,
    amountInCents,
    type,
    date,
    note,
    receiptPhotoUrl,
    isVoided,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LedgerEntryTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('party_id')) {
      context.handle(
        _partyIdMeta,
        partyId.isAcceptableOrUnknown(data['party_id']!, _partyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_partyIdMeta);
    }
    if (data.containsKey('amount_in_cents')) {
      context.handle(
        _amountInCentsMeta,
        amountInCents.isAcceptableOrUnknown(
          data['amount_in_cents']!,
          _amountInCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountInCentsMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('receipt_photo_url')) {
      context.handle(
        _receiptPhotoUrlMeta,
        receiptPhotoUrl.isAcceptableOrUnknown(
          data['receipt_photo_url']!,
          _receiptPhotoUrlMeta,
        ),
      );
    }
    if (data.containsKey('is_voided')) {
      context.handle(
        _isVoidedMeta,
        isVoided.isAcceptableOrUnknown(data['is_voided']!, _isVoidedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LedgerEntryTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerEntryTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      partyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}party_id'],
      )!,
      amountInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_in_cents'],
      )!,
      type: $LedgerEntriesTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}type'],
        )!,
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      receiptPhotoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_photo_url'],
      ),
      isVoided: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_voided'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LedgerEntriesTable createAlias(String alias) {
    return $LedgerEntriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EntryType, String, String> $convertertype =
      const EnumNameConverter<EntryType>(EntryType.values);
}

class LedgerEntryTableData extends DataClass
    implements Insertable<LedgerEntryTableData> {
  final String id;
  final String companyId;
  final String partyId;
  final int amountInCents;
  final EntryType type;
  final DateTime date;
  final String? note;
  final String? receiptPhotoUrl;
  final bool isVoided;
  final DateTime createdAt;
  const LedgerEntryTableData({
    required this.id,
    required this.companyId,
    required this.partyId,
    required this.amountInCents,
    required this.type,
    required this.date,
    this.note,
    this.receiptPhotoUrl,
    required this.isVoided,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['party_id'] = Variable<String>(partyId);
    map['amount_in_cents'] = Variable<int>(amountInCents);
    {
      map['type'] = Variable<String>(
        $LedgerEntriesTable.$convertertype.toSql(type),
      );
    }
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || receiptPhotoUrl != null) {
      map['receipt_photo_url'] = Variable<String>(receiptPhotoUrl);
    }
    map['is_voided'] = Variable<bool>(isVoided);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LedgerEntriesCompanion toCompanion(bool nullToAbsent) {
    return LedgerEntriesCompanion(
      id: Value(id),
      companyId: Value(companyId),
      partyId: Value(partyId),
      amountInCents: Value(amountInCents),
      type: Value(type),
      date: Value(date),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      receiptPhotoUrl: receiptPhotoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptPhotoUrl),
      isVoided: Value(isVoided),
      createdAt: Value(createdAt),
    );
  }

  factory LedgerEntryTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerEntryTableData(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      partyId: serializer.fromJson<String>(json['partyId']),
      amountInCents: serializer.fromJson<int>(json['amountInCents']),
      type: $LedgerEntriesTable.$convertertype.fromJson(
        serializer.fromJson<String>(json['type']),
      ),
      date: serializer.fromJson<DateTime>(json['date']),
      note: serializer.fromJson<String?>(json['note']),
      receiptPhotoUrl: serializer.fromJson<String?>(json['receiptPhotoUrl']),
      isVoided: serializer.fromJson<bool>(json['isVoided']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'partyId': serializer.toJson<String>(partyId),
      'amountInCents': serializer.toJson<int>(amountInCents),
      'type': serializer.toJson<String>(
        $LedgerEntriesTable.$convertertype.toJson(type),
      ),
      'date': serializer.toJson<DateTime>(date),
      'note': serializer.toJson<String?>(note),
      'receiptPhotoUrl': serializer.toJson<String?>(receiptPhotoUrl),
      'isVoided': serializer.toJson<bool>(isVoided),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LedgerEntryTableData copyWith({
    String? id,
    String? companyId,
    String? partyId,
    int? amountInCents,
    EntryType? type,
    DateTime? date,
    Value<String?> note = const Value.absent(),
    Value<String?> receiptPhotoUrl = const Value.absent(),
    bool? isVoided,
    DateTime? createdAt,
  }) => LedgerEntryTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    partyId: partyId ?? this.partyId,
    amountInCents: amountInCents ?? this.amountInCents,
    type: type ?? this.type,
    date: date ?? this.date,
    note: note.present ? note.value : this.note,
    receiptPhotoUrl: receiptPhotoUrl.present
        ? receiptPhotoUrl.value
        : this.receiptPhotoUrl,
    isVoided: isVoided ?? this.isVoided,
    createdAt: createdAt ?? this.createdAt,
  );
  LedgerEntryTableData copyWithCompanion(LedgerEntriesCompanion data) {
    return LedgerEntryTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      partyId: data.partyId.present ? data.partyId.value : this.partyId,
      amountInCents: data.amountInCents.present
          ? data.amountInCents.value
          : this.amountInCents,
      type: data.type.present ? data.type.value : this.type,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
      receiptPhotoUrl: data.receiptPhotoUrl.present
          ? data.receiptPhotoUrl.value
          : this.receiptPhotoUrl,
      isVoided: data.isVoided.present ? data.isVoided.value : this.isVoided,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerEntryTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('partyId: $partyId, ')
          ..write('amountInCents: $amountInCents, ')
          ..write('type: $type, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('receiptPhotoUrl: $receiptPhotoUrl, ')
          ..write('isVoided: $isVoided, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    partyId,
    amountInCents,
    type,
    date,
    note,
    receiptPhotoUrl,
    isVoided,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerEntryTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.partyId == this.partyId &&
          other.amountInCents == this.amountInCents &&
          other.type == this.type &&
          other.date == this.date &&
          other.note == this.note &&
          other.receiptPhotoUrl == this.receiptPhotoUrl &&
          other.isVoided == this.isVoided &&
          other.createdAt == this.createdAt);
}

class LedgerEntriesCompanion extends UpdateCompanion<LedgerEntryTableData> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> partyId;
  final Value<int> amountInCents;
  final Value<EntryType> type;
  final Value<DateTime> date;
  final Value<String?> note;
  final Value<String?> receiptPhotoUrl;
  final Value<bool> isVoided;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LedgerEntriesCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.partyId = const Value.absent(),
    this.amountInCents = const Value.absent(),
    this.type = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.receiptPhotoUrl = const Value.absent(),
    this.isVoided = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgerEntriesCompanion.insert({
    required String id,
    this.companyId = const Value.absent(),
    required String partyId,
    required int amountInCents,
    required EntryType type,
    required DateTime date,
    this.note = const Value.absent(),
    this.receiptPhotoUrl = const Value.absent(),
    this.isVoided = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       partyId = Value(partyId),
       amountInCents = Value(amountInCents),
       type = Value(type),
       date = Value(date);
  static Insertable<LedgerEntryTableData> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? partyId,
    Expression<int>? amountInCents,
    Expression<String>? type,
    Expression<DateTime>? date,
    Expression<String>? note,
    Expression<String>? receiptPhotoUrl,
    Expression<bool>? isVoided,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (partyId != null) 'party_id': partyId,
      if (amountInCents != null) 'amount_in_cents': amountInCents,
      if (type != null) 'type': type,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (receiptPhotoUrl != null) 'receipt_photo_url': receiptPhotoUrl,
      if (isVoided != null) 'is_voided': isVoided,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgerEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? partyId,
    Value<int>? amountInCents,
    Value<EntryType>? type,
    Value<DateTime>? date,
    Value<String?>? note,
    Value<String?>? receiptPhotoUrl,
    Value<bool>? isVoided,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LedgerEntriesCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      partyId: partyId ?? this.partyId,
      amountInCents: amountInCents ?? this.amountInCents,
      type: type ?? this.type,
      date: date ?? this.date,
      note: note ?? this.note,
      receiptPhotoUrl: receiptPhotoUrl ?? this.receiptPhotoUrl,
      isVoided: isVoided ?? this.isVoided,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (partyId.present) {
      map['party_id'] = Variable<String>(partyId.value);
    }
    if (amountInCents.present) {
      map['amount_in_cents'] = Variable<int>(amountInCents.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(
        $LedgerEntriesTable.$convertertype.toSql(type.value),
      );
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (receiptPhotoUrl.present) {
      map['receipt_photo_url'] = Variable<String>(receiptPhotoUrl.value);
    }
    if (isVoided.present) {
      map['is_voided'] = Variable<bool>(isVoided.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerEntriesCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('partyId: $partyId, ')
          ..write('amountInCents: $amountInCents, ')
          ..write('type: $type, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('receiptPhotoUrl: $receiptPhotoUrl, ')
          ..write('isVoided: $isVoided, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuditLogsTable extends AuditLogs
    with TableInfo<$AuditLogsTable, AuditLogTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuditLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oldStateJsonMeta = const VerificationMeta(
    'oldStateJson',
  );
  @override
  late final GeneratedColumn<String> oldStateJson = GeneratedColumn<String>(
    'old_state_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newStateJsonMeta = const VerificationMeta(
    'newStateJson',
  );
  @override
  late final GeneratedColumn<String> newStateJson = GeneratedColumn<String>(
    'new_state_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _diffJsonMeta = const VerificationMeta(
    'diffJson',
  );
  @override
  late final GeneratedColumn<String> diffJson = GeneratedColumn<String>(
    'diff_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checksumMeta = const VerificationMeta(
    'checksum',
  );
  @override
  late final GeneratedColumn<String> checksum = GeneratedColumn<String>(
    'checksum',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previousChecksumMeta = const VerificationMeta(
    'previousChecksum',
  );
  @override
  late final GeneratedColumn<String> previousChecksum = GeneratedColumn<String>(
    'previous_checksum',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    userId,
    entityType,
    entityId,
    action,
    timestamp,
    oldStateJson,
    newStateJson,
    diffJson,
    checksum,
    previousChecksum,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audit_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<AuditLogTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_companyIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('old_state_json')) {
      context.handle(
        _oldStateJsonMeta,
        oldStateJson.isAcceptableOrUnknown(
          data['old_state_json']!,
          _oldStateJsonMeta,
        ),
      );
    }
    if (data.containsKey('new_state_json')) {
      context.handle(
        _newStateJsonMeta,
        newStateJson.isAcceptableOrUnknown(
          data['new_state_json']!,
          _newStateJsonMeta,
        ),
      );
    }
    if (data.containsKey('diff_json')) {
      context.handle(
        _diffJsonMeta,
        diffJson.isAcceptableOrUnknown(data['diff_json']!, _diffJsonMeta),
      );
    }
    if (data.containsKey('checksum')) {
      context.handle(
        _checksumMeta,
        checksum.isAcceptableOrUnknown(data['checksum']!, _checksumMeta),
      );
    } else if (isInserting) {
      context.missing(_checksumMeta);
    }
    if (data.containsKey('previous_checksum')) {
      context.handle(
        _previousChecksumMeta,
        previousChecksum.isAcceptableOrUnknown(
          data['previous_checksum']!,
          _previousChecksumMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AuditLogTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AuditLogTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      oldStateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}old_state_json'],
      ),
      newStateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_state_json'],
      ),
      diffJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diff_json'],
      ),
      checksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checksum'],
      )!,
      previousChecksum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_checksum'],
      ),
    );
  }

  @override
  $AuditLogsTable createAlias(String alias) {
    return $AuditLogsTable(attachedDatabase, alias);
  }
}

class AuditLogTableData extends DataClass
    implements Insertable<AuditLogTableData> {
  final String id;
  final String companyId;
  final String userId;
  final String entityType;
  final String entityId;
  final String action;
  final DateTime timestamp;
  final String? oldStateJson;
  final String? newStateJson;
  final String? diffJson;
  final String checksum;
  final String? previousChecksum;
  const AuditLogTableData({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.timestamp,
    this.oldStateJson,
    this.newStateJson,
    this.diffJson,
    required this.checksum,
    this.previousChecksum,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || oldStateJson != null) {
      map['old_state_json'] = Variable<String>(oldStateJson);
    }
    if (!nullToAbsent || newStateJson != null) {
      map['new_state_json'] = Variable<String>(newStateJson);
    }
    if (!nullToAbsent || diffJson != null) {
      map['diff_json'] = Variable<String>(diffJson);
    }
    map['checksum'] = Variable<String>(checksum);
    if (!nullToAbsent || previousChecksum != null) {
      map['previous_checksum'] = Variable<String>(previousChecksum);
    }
    return map;
  }

  AuditLogsCompanion toCompanion(bool nullToAbsent) {
    return AuditLogsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      userId: Value(userId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action),
      timestamp: Value(timestamp),
      oldStateJson: oldStateJson == null && nullToAbsent
          ? const Value.absent()
          : Value(oldStateJson),
      newStateJson: newStateJson == null && nullToAbsent
          ? const Value.absent()
          : Value(newStateJson),
      diffJson: diffJson == null && nullToAbsent
          ? const Value.absent()
          : Value(diffJson),
      checksum: Value(checksum),
      previousChecksum: previousChecksum == null && nullToAbsent
          ? const Value.absent()
          : Value(previousChecksum),
    );
  }

  factory AuditLogTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AuditLogTableData(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      userId: serializer.fromJson<String>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      oldStateJson: serializer.fromJson<String?>(json['oldStateJson']),
      newStateJson: serializer.fromJson<String?>(json['newStateJson']),
      diffJson: serializer.fromJson<String?>(json['diffJson']),
      checksum: serializer.fromJson<String>(json['checksum']),
      previousChecksum: serializer.fromJson<String?>(json['previousChecksum']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'userId': serializer.toJson<String>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'oldStateJson': serializer.toJson<String?>(oldStateJson),
      'newStateJson': serializer.toJson<String?>(newStateJson),
      'diffJson': serializer.toJson<String?>(diffJson),
      'checksum': serializer.toJson<String>(checksum),
      'previousChecksum': serializer.toJson<String?>(previousChecksum),
    };
  }

  AuditLogTableData copyWith({
    String? id,
    String? companyId,
    String? userId,
    String? entityType,
    String? entityId,
    String? action,
    DateTime? timestamp,
    Value<String?> oldStateJson = const Value.absent(),
    Value<String?> newStateJson = const Value.absent(),
    Value<String?> diffJson = const Value.absent(),
    String? checksum,
    Value<String?> previousChecksum = const Value.absent(),
  }) => AuditLogTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    timestamp: timestamp ?? this.timestamp,
    oldStateJson: oldStateJson.present ? oldStateJson.value : this.oldStateJson,
    newStateJson: newStateJson.present ? newStateJson.value : this.newStateJson,
    diffJson: diffJson.present ? diffJson.value : this.diffJson,
    checksum: checksum ?? this.checksum,
    previousChecksum: previousChecksum.present
        ? previousChecksum.value
        : this.previousChecksum,
  );
  AuditLogTableData copyWithCompanion(AuditLogsCompanion data) {
    return AuditLogTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      oldStateJson: data.oldStateJson.present
          ? data.oldStateJson.value
          : this.oldStateJson,
      newStateJson: data.newStateJson.present
          ? data.newStateJson.value
          : this.newStateJson,
      diffJson: data.diffJson.present ? data.diffJson.value : this.diffJson,
      checksum: data.checksum.present ? data.checksum.value : this.checksum,
      previousChecksum: data.previousChecksum.present
          ? data.previousChecksum.value
          : this.previousChecksum,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AuditLogTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('timestamp: $timestamp, ')
          ..write('oldStateJson: $oldStateJson, ')
          ..write('newStateJson: $newStateJson, ')
          ..write('diffJson: $diffJson, ')
          ..write('checksum: $checksum, ')
          ..write('previousChecksum: $previousChecksum')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    userId,
    entityType,
    entityId,
    action,
    timestamp,
    oldStateJson,
    newStateJson,
    diffJson,
    checksum,
    previousChecksum,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuditLogTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.timestamp == this.timestamp &&
          other.oldStateJson == this.oldStateJson &&
          other.newStateJson == this.newStateJson &&
          other.diffJson == this.diffJson &&
          other.checksum == this.checksum &&
          other.previousChecksum == this.previousChecksum);
}

class AuditLogsCompanion extends UpdateCompanion<AuditLogTableData> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> userId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> action;
  final Value<DateTime> timestamp;
  final Value<String?> oldStateJson;
  final Value<String?> newStateJson;
  final Value<String?> diffJson;
  final Value<String> checksum;
  final Value<String?> previousChecksum;
  final Value<int> rowid;
  const AuditLogsCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.oldStateJson = const Value.absent(),
    this.newStateJson = const Value.absent(),
    this.diffJson = const Value.absent(),
    this.checksum = const Value.absent(),
    this.previousChecksum = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuditLogsCompanion.insert({
    required String id,
    required String companyId,
    required String userId,
    required String entityType,
    required String entityId,
    required String action,
    required DateTime timestamp,
    this.oldStateJson = const Value.absent(),
    this.newStateJson = const Value.absent(),
    this.diffJson = const Value.absent(),
    required String checksum,
    this.previousChecksum = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       companyId = Value(companyId),
       userId = Value(userId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       action = Value(action),
       timestamp = Value(timestamp),
       checksum = Value(checksum);
  static Insertable<AuditLogTableData> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<DateTime>? timestamp,
    Expression<String>? oldStateJson,
    Expression<String>? newStateJson,
    Expression<String>? diffJson,
    Expression<String>? checksum,
    Expression<String>? previousChecksum,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (timestamp != null) 'timestamp': timestamp,
      if (oldStateJson != null) 'old_state_json': oldStateJson,
      if (newStateJson != null) 'new_state_json': newStateJson,
      if (diffJson != null) 'diff_json': diffJson,
      if (checksum != null) 'checksum': checksum,
      if (previousChecksum != null) 'previous_checksum': previousChecksum,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuditLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? userId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? action,
    Value<DateTime>? timestamp,
    Value<String?>? oldStateJson,
    Value<String?>? newStateJson,
    Value<String?>? diffJson,
    Value<String>? checksum,
    Value<String?>? previousChecksum,
    Value<int>? rowid,
  }) {
    return AuditLogsCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      timestamp: timestamp ?? this.timestamp,
      oldStateJson: oldStateJson ?? this.oldStateJson,
      newStateJson: newStateJson ?? this.newStateJson,
      diffJson: diffJson ?? this.diffJson,
      checksum: checksum ?? this.checksum,
      previousChecksum: previousChecksum ?? this.previousChecksum,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (oldStateJson.present) {
      map['old_state_json'] = Variable<String>(oldStateJson.value);
    }
    if (newStateJson.present) {
      map['new_state_json'] = Variable<String>(newStateJson.value);
    }
    if (diffJson.present) {
      map['diff_json'] = Variable<String>(diffJson.value);
    }
    if (checksum.present) {
      map['checksum'] = Variable<String>(checksum.value);
    }
    if (previousChecksum.present) {
      map['previous_checksum'] = Variable<String>(previousChecksum.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuditLogsCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('timestamp: $timestamp, ')
          ..write('oldStateJson: $oldStateJson, ')
          ..write('newStateJson: $newStateJson, ')
          ..write('diffJson: $diffJson, ')
          ..write('checksum: $checksum, ')
          ..write('previousChecksum: $previousChecksum, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cmp_default'),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    entityType,
    entityId,
    action,
    payload,
    createdAt,
    status,
    retryCount,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxTableData extends DataClass
    implements Insertable<SyncOutboxTableData> {
  final int id;
  final String companyId;
  final String entityType;
  final String entityId;
  final String action;
  final String payload;
  final DateTime createdAt;
  final String status;
  final int retryCount;
  final String? lastError;
  const SyncOutboxTableData({
    required this.id,
    required this.companyId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    required this.createdAt,
    required this.status,
    required this.retryCount,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['company_id'] = Variable<String>(companyId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      companyId: Value(companyId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action),
      payload: Value(payload),
      createdAt: Value(createdAt),
      status: Value(status),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncOutboxTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxTableData(
      id: serializer.fromJson<int>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'companyId': serializer.toJson<String>(companyId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncOutboxTableData copyWith({
    int? id,
    String? companyId,
    String? entityType,
    String? entityId,
    String? action,
    String? payload,
    DateTime? createdAt,
    String? status,
    int? retryCount,
    Value<String?> lastError = const Value.absent(),
  }) => SyncOutboxTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncOutboxTableData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    entityType,
    entityId,
    action,
    payload,
    createdAt,
    status,
    retryCount,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxTableData> {
  final Value<int> id;
  final Value<String> companyId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> action;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<String?> lastError;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    required String entityType,
    required String entityId,
    required String action,
    required String payload,
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       action = Value(action),
       payload = Value(payload);
  static Insertable<SyncOutboxTableData> custom({
    Expression<int>? id,
    Expression<String>? companyId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? companyId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? action,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<String>? status,
    Value<int>? retryCount,
    Value<String?>? lastError,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $InventoryItemsTable extends InventoryItems
    with TableInfo<$InventoryItemsTable, InventoryItemTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cmp_default'),
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PCS'),
  );
  static const VerificationMeta _purchasePriceInCentsMeta =
      const VerificationMeta('purchasePriceInCents');
  @override
  late final GeneratedColumn<int> purchasePriceInCents = GeneratedColumn<int>(
    'purchase_price_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sellingPriceInCentsMeta =
      const VerificationMeta('sellingPriceInCents');
  @override
  late final GeneratedColumn<int> sellingPriceInCents = GeneratedColumn<int>(
    'selling_price_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _currentStockQuantityMeta =
      const VerificationMeta('currentStockQuantity');
  @override
  late final GeneratedColumn<double> currentStockQuantity =
      GeneratedColumn<double>(
        'current_stock_quantity',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.0),
      );
  static const VerificationMeta _minimumStockAlertMeta = const VerificationMeta(
    'minimumStockAlert',
  );
  @override
  late final GeneratedColumn<double> minimumStockAlert =
      GeneratedColumn<double>(
        'minimum_stock_alert',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(5.0),
      );
  static const VerificationMeta _hsnCodeMeta = const VerificationMeta(
    'hsnCode',
  );
  @override
  late final GeneratedColumn<String> hsnCode = GeneratedColumn<String>(
    'hsn_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taxRatePercentMeta = const VerificationMeta(
    'taxRatePercent',
  );
  @override
  late final GeneratedColumn<double> taxRatePercent = GeneratedColumn<double>(
    'tax_rate_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    sku,
    name,
    description,
    unit,
    purchasePriceInCents,
    sellingPriceInCents,
    currentStockQuantity,
    minimumStockAlert,
    hsnCode,
    taxRatePercent,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryItemTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('purchase_price_in_cents')) {
      context.handle(
        _purchasePriceInCentsMeta,
        purchasePriceInCents.isAcceptableOrUnknown(
          data['purchase_price_in_cents']!,
          _purchasePriceInCentsMeta,
        ),
      );
    }
    if (data.containsKey('selling_price_in_cents')) {
      context.handle(
        _sellingPriceInCentsMeta,
        sellingPriceInCents.isAcceptableOrUnknown(
          data['selling_price_in_cents']!,
          _sellingPriceInCentsMeta,
        ),
      );
    }
    if (data.containsKey('current_stock_quantity')) {
      context.handle(
        _currentStockQuantityMeta,
        currentStockQuantity.isAcceptableOrUnknown(
          data['current_stock_quantity']!,
          _currentStockQuantityMeta,
        ),
      );
    }
    if (data.containsKey('minimum_stock_alert')) {
      context.handle(
        _minimumStockAlertMeta,
        minimumStockAlert.isAcceptableOrUnknown(
          data['minimum_stock_alert']!,
          _minimumStockAlertMeta,
        ),
      );
    }
    if (data.containsKey('hsn_code')) {
      context.handle(
        _hsnCodeMeta,
        hsnCode.isAcceptableOrUnknown(data['hsn_code']!, _hsnCodeMeta),
      );
    }
    if (data.containsKey('tax_rate_percent')) {
      context.handle(
        _taxRatePercentMeta,
        taxRatePercent.isAcceptableOrUnknown(
          data['tax_rate_percent']!,
          _taxRatePercentMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryItemTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryItemTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      purchasePriceInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}purchase_price_in_cents'],
      )!,
      sellingPriceInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}selling_price_in_cents'],
      )!,
      currentStockQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}current_stock_quantity'],
      )!,
      minimumStockAlert: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}minimum_stock_alert'],
      )!,
      hsnCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hsn_code'],
      ),
      taxRatePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tax_rate_percent'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InventoryItemsTable createAlias(String alias) {
    return $InventoryItemsTable(attachedDatabase, alias);
  }
}

class InventoryItemTableData extends DataClass
    implements Insertable<InventoryItemTableData> {
  final String id;
  final String companyId;
  final String sku;
  final String name;
  final String? description;
  final String unit;
  final int purchasePriceInCents;
  final int sellingPriceInCents;
  final double currentStockQuantity;
  final double minimumStockAlert;
  final String? hsnCode;
  final double taxRatePercent;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const InventoryItemTableData({
    required this.id,
    required this.companyId,
    required this.sku,
    required this.name,
    this.description,
    required this.unit,
    required this.purchasePriceInCents,
    required this.sellingPriceInCents,
    required this.currentStockQuantity,
    required this.minimumStockAlert,
    this.hsnCode,
    required this.taxRatePercent,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['sku'] = Variable<String>(sku);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['unit'] = Variable<String>(unit);
    map['purchase_price_in_cents'] = Variable<int>(purchasePriceInCents);
    map['selling_price_in_cents'] = Variable<int>(sellingPriceInCents);
    map['current_stock_quantity'] = Variable<double>(currentStockQuantity);
    map['minimum_stock_alert'] = Variable<double>(minimumStockAlert);
    if (!nullToAbsent || hsnCode != null) {
      map['hsn_code'] = Variable<String>(hsnCode);
    }
    map['tax_rate_percent'] = Variable<double>(taxRatePercent);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  InventoryItemsCompanion toCompanion(bool nullToAbsent) {
    return InventoryItemsCompanion(
      id: Value(id),
      companyId: Value(companyId),
      sku: Value(sku),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      unit: Value(unit),
      purchasePriceInCents: Value(purchasePriceInCents),
      sellingPriceInCents: Value(sellingPriceInCents),
      currentStockQuantity: Value(currentStockQuantity),
      minimumStockAlert: Value(minimumStockAlert),
      hsnCode: hsnCode == null && nullToAbsent
          ? const Value.absent()
          : Value(hsnCode),
      taxRatePercent: Value(taxRatePercent),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory InventoryItemTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryItemTableData(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      sku: serializer.fromJson<String>(json['sku']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      unit: serializer.fromJson<String>(json['unit']),
      purchasePriceInCents: serializer.fromJson<int>(
        json['purchasePriceInCents'],
      ),
      sellingPriceInCents: serializer.fromJson<int>(
        json['sellingPriceInCents'],
      ),
      currentStockQuantity: serializer.fromJson<double>(
        json['currentStockQuantity'],
      ),
      minimumStockAlert: serializer.fromJson<double>(json['minimumStockAlert']),
      hsnCode: serializer.fromJson<String?>(json['hsnCode']),
      taxRatePercent: serializer.fromJson<double>(json['taxRatePercent']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'sku': serializer.toJson<String>(sku),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'unit': serializer.toJson<String>(unit),
      'purchasePriceInCents': serializer.toJson<int>(purchasePriceInCents),
      'sellingPriceInCents': serializer.toJson<int>(sellingPriceInCents),
      'currentStockQuantity': serializer.toJson<double>(currentStockQuantity),
      'minimumStockAlert': serializer.toJson<double>(minimumStockAlert),
      'hsnCode': serializer.toJson<String?>(hsnCode),
      'taxRatePercent': serializer.toJson<double>(taxRatePercent),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  InventoryItemTableData copyWith({
    String? id,
    String? companyId,
    String? sku,
    String? name,
    Value<String?> description = const Value.absent(),
    String? unit,
    int? purchasePriceInCents,
    int? sellingPriceInCents,
    double? currentStockQuantity,
    double? minimumStockAlert,
    Value<String?> hsnCode = const Value.absent(),
    double? taxRatePercent,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InventoryItemTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    sku: sku ?? this.sku,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    unit: unit ?? this.unit,
    purchasePriceInCents: purchasePriceInCents ?? this.purchasePriceInCents,
    sellingPriceInCents: sellingPriceInCents ?? this.sellingPriceInCents,
    currentStockQuantity: currentStockQuantity ?? this.currentStockQuantity,
    minimumStockAlert: minimumStockAlert ?? this.minimumStockAlert,
    hsnCode: hsnCode.present ? hsnCode.value : this.hsnCode,
    taxRatePercent: taxRatePercent ?? this.taxRatePercent,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InventoryItemTableData copyWithCompanion(InventoryItemsCompanion data) {
    return InventoryItemTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      sku: data.sku.present ? data.sku.value : this.sku,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      unit: data.unit.present ? data.unit.value : this.unit,
      purchasePriceInCents: data.purchasePriceInCents.present
          ? data.purchasePriceInCents.value
          : this.purchasePriceInCents,
      sellingPriceInCents: data.sellingPriceInCents.present
          ? data.sellingPriceInCents.value
          : this.sellingPriceInCents,
      currentStockQuantity: data.currentStockQuantity.present
          ? data.currentStockQuantity.value
          : this.currentStockQuantity,
      minimumStockAlert: data.minimumStockAlert.present
          ? data.minimumStockAlert.value
          : this.minimumStockAlert,
      hsnCode: data.hsnCode.present ? data.hsnCode.value : this.hsnCode,
      taxRatePercent: data.taxRatePercent.present
          ? data.taxRatePercent.value
          : this.taxRatePercent,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryItemTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('sku: $sku, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('unit: $unit, ')
          ..write('purchasePriceInCents: $purchasePriceInCents, ')
          ..write('sellingPriceInCents: $sellingPriceInCents, ')
          ..write('currentStockQuantity: $currentStockQuantity, ')
          ..write('minimumStockAlert: $minimumStockAlert, ')
          ..write('hsnCode: $hsnCode, ')
          ..write('taxRatePercent: $taxRatePercent, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    sku,
    name,
    description,
    unit,
    purchasePriceInCents,
    sellingPriceInCents,
    currentStockQuantity,
    minimumStockAlert,
    hsnCode,
    taxRatePercent,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryItemTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.sku == this.sku &&
          other.name == this.name &&
          other.description == this.description &&
          other.unit == this.unit &&
          other.purchasePriceInCents == this.purchasePriceInCents &&
          other.sellingPriceInCents == this.sellingPriceInCents &&
          other.currentStockQuantity == this.currentStockQuantity &&
          other.minimumStockAlert == this.minimumStockAlert &&
          other.hsnCode == this.hsnCode &&
          other.taxRatePercent == this.taxRatePercent &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class InventoryItemsCompanion extends UpdateCompanion<InventoryItemTableData> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> sku;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> unit;
  final Value<int> purchasePriceInCents;
  final Value<int> sellingPriceInCents;
  final Value<double> currentStockQuantity;
  final Value<double> minimumStockAlert;
  final Value<String?> hsnCode;
  final Value<double> taxRatePercent;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const InventoryItemsCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.sku = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.unit = const Value.absent(),
    this.purchasePriceInCents = const Value.absent(),
    this.sellingPriceInCents = const Value.absent(),
    this.currentStockQuantity = const Value.absent(),
    this.minimumStockAlert = const Value.absent(),
    this.hsnCode = const Value.absent(),
    this.taxRatePercent = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryItemsCompanion.insert({
    required String id,
    this.companyId = const Value.absent(),
    required String sku,
    required String name,
    this.description = const Value.absent(),
    this.unit = const Value.absent(),
    this.purchasePriceInCents = const Value.absent(),
    this.sellingPriceInCents = const Value.absent(),
    this.currentStockQuantity = const Value.absent(),
    this.minimumStockAlert = const Value.absent(),
    this.hsnCode = const Value.absent(),
    this.taxRatePercent = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sku = Value(sku),
       name = Value(name);
  static Insertable<InventoryItemTableData> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? sku,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? unit,
    Expression<int>? purchasePriceInCents,
    Expression<int>? sellingPriceInCents,
    Expression<double>? currentStockQuantity,
    Expression<double>? minimumStockAlert,
    Expression<String>? hsnCode,
    Expression<double>? taxRatePercent,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (sku != null) 'sku': sku,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (unit != null) 'unit': unit,
      if (purchasePriceInCents != null)
        'purchase_price_in_cents': purchasePriceInCents,
      if (sellingPriceInCents != null)
        'selling_price_in_cents': sellingPriceInCents,
      if (currentStockQuantity != null)
        'current_stock_quantity': currentStockQuantity,
      if (minimumStockAlert != null) 'minimum_stock_alert': minimumStockAlert,
      if (hsnCode != null) 'hsn_code': hsnCode,
      if (taxRatePercent != null) 'tax_rate_percent': taxRatePercent,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? sku,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? unit,
    Value<int>? purchasePriceInCents,
    Value<int>? sellingPriceInCents,
    Value<double>? currentStockQuantity,
    Value<double>? minimumStockAlert,
    Value<String?>? hsnCode,
    Value<double>? taxRatePercent,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return InventoryItemsCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      purchasePriceInCents: purchasePriceInCents ?? this.purchasePriceInCents,
      sellingPriceInCents: sellingPriceInCents ?? this.sellingPriceInCents,
      currentStockQuantity: currentStockQuantity ?? this.currentStockQuantity,
      minimumStockAlert: minimumStockAlert ?? this.minimumStockAlert,
      hsnCode: hsnCode ?? this.hsnCode,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (purchasePriceInCents.present) {
      map['purchase_price_in_cents'] = Variable<int>(
        purchasePriceInCents.value,
      );
    }
    if (sellingPriceInCents.present) {
      map['selling_price_in_cents'] = Variable<int>(sellingPriceInCents.value);
    }
    if (currentStockQuantity.present) {
      map['current_stock_quantity'] = Variable<double>(
        currentStockQuantity.value,
      );
    }
    if (minimumStockAlert.present) {
      map['minimum_stock_alert'] = Variable<double>(minimumStockAlert.value);
    }
    if (hsnCode.present) {
      map['hsn_code'] = Variable<String>(hsnCode.value);
    }
    if (taxRatePercent.present) {
      map['tax_rate_percent'] = Variable<double>(taxRatePercent.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryItemsCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('sku: $sku, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('unit: $unit, ')
          ..write('purchasePriceInCents: $purchasePriceInCents, ')
          ..write('sellingPriceInCents: $sellingPriceInCents, ')
          ..write('currentStockQuantity: $currentStockQuantity, ')
          ..write('minimumStockAlert: $minimumStockAlert, ')
          ..write('hsnCode: $hsnCode, ')
          ..write('taxRatePercent: $taxRatePercent, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockLedgerTable extends StockLedger
    with TableInfo<$StockLedgerTable, StockLedgerTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockLedgerTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cmp_default'),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES inventory_items (id)',
    ),
  );
  static const VerificationMeta _voucherIdMeta = const VerificationMeta(
    'voucherId',
  );
  @override
  late final GeneratedColumn<String> voucherId = GeneratedColumn<String>(
    'voucher_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transactionTypeMeta = const VerificationMeta(
    'transactionType',
  );
  @override
  late final GeneratedColumn<String> transactionType = GeneratedColumn<String>(
    'transaction_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitCostInCentsMeta = const VerificationMeta(
    'unitCostInCents',
  );
  @override
  late final GeneratedColumn<int> unitCostInCents = GeneratedColumn<int>(
    'unit_cost_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalCostInCentsMeta = const VerificationMeta(
    'totalCostInCents',
  );
  @override
  late final GeneratedColumn<int> totalCostInCents = GeneratedColumn<int>(
    'total_cost_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _runningStockQuantityMeta =
      const VerificationMeta('runningStockQuantity');
  @override
  late final GeneratedColumn<double> runningStockQuantity =
      GeneratedColumn<double>(
        'running_stock_quantity',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.0),
      );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    itemId,
    voucherId,
    transactionType,
    quantity,
    unitCostInCents,
    totalCostInCents,
    runningStockQuantity,
    date,
    note,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_ledger';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockLedgerTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('voucher_id')) {
      context.handle(
        _voucherIdMeta,
        voucherId.isAcceptableOrUnknown(data['voucher_id']!, _voucherIdMeta),
      );
    }
    if (data.containsKey('transaction_type')) {
      context.handle(
        _transactionTypeMeta,
        transactionType.isAcceptableOrUnknown(
          data['transaction_type']!,
          _transactionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionTypeMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_cost_in_cents')) {
      context.handle(
        _unitCostInCentsMeta,
        unitCostInCents.isAcceptableOrUnknown(
          data['unit_cost_in_cents']!,
          _unitCostInCentsMeta,
        ),
      );
    }
    if (data.containsKey('total_cost_in_cents')) {
      context.handle(
        _totalCostInCentsMeta,
        totalCostInCents.isAcceptableOrUnknown(
          data['total_cost_in_cents']!,
          _totalCostInCentsMeta,
        ),
      );
    }
    if (data.containsKey('running_stock_quantity')) {
      context.handle(
        _runningStockQuantityMeta,
        runningStockQuantity.isAcceptableOrUnknown(
          data['running_stock_quantity']!,
          _runningStockQuantityMeta,
        ),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockLedgerTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockLedgerTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      voucherId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voucher_id'],
      ),
      transactionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_type'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
      unitCostInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_cost_in_cents'],
      )!,
      totalCostInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_cost_in_cents'],
      )!,
      runningStockQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}running_stock_quantity'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $StockLedgerTable createAlias(String alias) {
    return $StockLedgerTable(attachedDatabase, alias);
  }
}

class StockLedgerTableData extends DataClass
    implements Insertable<StockLedgerTableData> {
  final String id;
  final String companyId;
  final String itemId;
  final String? voucherId;
  final String transactionType;
  final double quantity;
  final int unitCostInCents;
  final int totalCostInCents;
  final double runningStockQuantity;
  final DateTime date;
  final String? note;
  final DateTime createdAt;
  const StockLedgerTableData({
    required this.id,
    required this.companyId,
    required this.itemId,
    this.voucherId,
    required this.transactionType,
    required this.quantity,
    required this.unitCostInCents,
    required this.totalCostInCents,
    required this.runningStockQuantity,
    required this.date,
    this.note,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || voucherId != null) {
      map['voucher_id'] = Variable<String>(voucherId);
    }
    map['transaction_type'] = Variable<String>(transactionType);
    map['quantity'] = Variable<double>(quantity);
    map['unit_cost_in_cents'] = Variable<int>(unitCostInCents);
    map['total_cost_in_cents'] = Variable<int>(totalCostInCents);
    map['running_stock_quantity'] = Variable<double>(runningStockQuantity);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  StockLedgerCompanion toCompanion(bool nullToAbsent) {
    return StockLedgerCompanion(
      id: Value(id),
      companyId: Value(companyId),
      itemId: Value(itemId),
      voucherId: voucherId == null && nullToAbsent
          ? const Value.absent()
          : Value(voucherId),
      transactionType: Value(transactionType),
      quantity: Value(quantity),
      unitCostInCents: Value(unitCostInCents),
      totalCostInCents: Value(totalCostInCents),
      runningStockQuantity: Value(runningStockQuantity),
      date: Value(date),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory StockLedgerTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockLedgerTableData(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      voucherId: serializer.fromJson<String?>(json['voucherId']),
      transactionType: serializer.fromJson<String>(json['transactionType']),
      quantity: serializer.fromJson<double>(json['quantity']),
      unitCostInCents: serializer.fromJson<int>(json['unitCostInCents']),
      totalCostInCents: serializer.fromJson<int>(json['totalCostInCents']),
      runningStockQuantity: serializer.fromJson<double>(
        json['runningStockQuantity'],
      ),
      date: serializer.fromJson<DateTime>(json['date']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'itemId': serializer.toJson<String>(itemId),
      'voucherId': serializer.toJson<String?>(voucherId),
      'transactionType': serializer.toJson<String>(transactionType),
      'quantity': serializer.toJson<double>(quantity),
      'unitCostInCents': serializer.toJson<int>(unitCostInCents),
      'totalCostInCents': serializer.toJson<int>(totalCostInCents),
      'runningStockQuantity': serializer.toJson<double>(runningStockQuantity),
      'date': serializer.toJson<DateTime>(date),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  StockLedgerTableData copyWith({
    String? id,
    String? companyId,
    String? itemId,
    Value<String?> voucherId = const Value.absent(),
    String? transactionType,
    double? quantity,
    int? unitCostInCents,
    int? totalCostInCents,
    double? runningStockQuantity,
    DateTime? date,
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
  }) => StockLedgerTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    itemId: itemId ?? this.itemId,
    voucherId: voucherId.present ? voucherId.value : this.voucherId,
    transactionType: transactionType ?? this.transactionType,
    quantity: quantity ?? this.quantity,
    unitCostInCents: unitCostInCents ?? this.unitCostInCents,
    totalCostInCents: totalCostInCents ?? this.totalCostInCents,
    runningStockQuantity: runningStockQuantity ?? this.runningStockQuantity,
    date: date ?? this.date,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
  );
  StockLedgerTableData copyWithCompanion(StockLedgerCompanion data) {
    return StockLedgerTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      voucherId: data.voucherId.present ? data.voucherId.value : this.voucherId,
      transactionType: data.transactionType.present
          ? data.transactionType.value
          : this.transactionType,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitCostInCents: data.unitCostInCents.present
          ? data.unitCostInCents.value
          : this.unitCostInCents,
      totalCostInCents: data.totalCostInCents.present
          ? data.totalCostInCents.value
          : this.totalCostInCents,
      runningStockQuantity: data.runningStockQuantity.present
          ? data.runningStockQuantity.value
          : this.runningStockQuantity,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockLedgerTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('itemId: $itemId, ')
          ..write('voucherId: $voucherId, ')
          ..write('transactionType: $transactionType, ')
          ..write('quantity: $quantity, ')
          ..write('unitCostInCents: $unitCostInCents, ')
          ..write('totalCostInCents: $totalCostInCents, ')
          ..write('runningStockQuantity: $runningStockQuantity, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    itemId,
    voucherId,
    transactionType,
    quantity,
    unitCostInCents,
    totalCostInCents,
    runningStockQuantity,
    date,
    note,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockLedgerTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.itemId == this.itemId &&
          other.voucherId == this.voucherId &&
          other.transactionType == this.transactionType &&
          other.quantity == this.quantity &&
          other.unitCostInCents == this.unitCostInCents &&
          other.totalCostInCents == this.totalCostInCents &&
          other.runningStockQuantity == this.runningStockQuantity &&
          other.date == this.date &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class StockLedgerCompanion extends UpdateCompanion<StockLedgerTableData> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> itemId;
  final Value<String?> voucherId;
  final Value<String> transactionType;
  final Value<double> quantity;
  final Value<int> unitCostInCents;
  final Value<int> totalCostInCents;
  final Value<double> runningStockQuantity;
  final Value<DateTime> date;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const StockLedgerCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.voucherId = const Value.absent(),
    this.transactionType = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitCostInCents = const Value.absent(),
    this.totalCostInCents = const Value.absent(),
    this.runningStockQuantity = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockLedgerCompanion.insert({
    required String id,
    this.companyId = const Value.absent(),
    required String itemId,
    this.voucherId = const Value.absent(),
    required String transactionType,
    required double quantity,
    this.unitCostInCents = const Value.absent(),
    this.totalCostInCents = const Value.absent(),
    this.runningStockQuantity = const Value.absent(),
    required DateTime date,
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       itemId = Value(itemId),
       transactionType = Value(transactionType),
       quantity = Value(quantity),
       date = Value(date);
  static Insertable<StockLedgerTableData> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? itemId,
    Expression<String>? voucherId,
    Expression<String>? transactionType,
    Expression<double>? quantity,
    Expression<int>? unitCostInCents,
    Expression<int>? totalCostInCents,
    Expression<double>? runningStockQuantity,
    Expression<DateTime>? date,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (itemId != null) 'item_id': itemId,
      if (voucherId != null) 'voucher_id': voucherId,
      if (transactionType != null) 'transaction_type': transactionType,
      if (quantity != null) 'quantity': quantity,
      if (unitCostInCents != null) 'unit_cost_in_cents': unitCostInCents,
      if (totalCostInCents != null) 'total_cost_in_cents': totalCostInCents,
      if (runningStockQuantity != null)
        'running_stock_quantity': runningStockQuantity,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockLedgerCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? itemId,
    Value<String?>? voucherId,
    Value<String>? transactionType,
    Value<double>? quantity,
    Value<int>? unitCostInCents,
    Value<int>? totalCostInCents,
    Value<double>? runningStockQuantity,
    Value<DateTime>? date,
    Value<String?>? note,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return StockLedgerCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      itemId: itemId ?? this.itemId,
      voucherId: voucherId ?? this.voucherId,
      transactionType: transactionType ?? this.transactionType,
      quantity: quantity ?? this.quantity,
      unitCostInCents: unitCostInCents ?? this.unitCostInCents,
      totalCostInCents: totalCostInCents ?? this.totalCostInCents,
      runningStockQuantity: runningStockQuantity ?? this.runningStockQuantity,
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (voucherId.present) {
      map['voucher_id'] = Variable<String>(voucherId.value);
    }
    if (transactionType.present) {
      map['transaction_type'] = Variable<String>(transactionType.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    if (unitCostInCents.present) {
      map['unit_cost_in_cents'] = Variable<int>(unitCostInCents.value);
    }
    if (totalCostInCents.present) {
      map['total_cost_in_cents'] = Variable<int>(totalCostInCents.value);
    }
    if (runningStockQuantity.present) {
      map['running_stock_quantity'] = Variable<double>(
        runningStockQuantity.value,
      );
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockLedgerCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('itemId: $itemId, ')
          ..write('voucherId: $voucherId, ')
          ..write('transactionType: $transactionType, ')
          ..write('quantity: $quantity, ')
          ..write('unitCostInCents: $unitCostInCents, ')
          ..write('totalCostInCents: $totalCostInCents, ')
          ..write('runningStockQuantity: $runningStockQuantity, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VouchersTable extends Vouchers
    with TableInfo<$VouchersTable, VoucherTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VouchersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<String> companyId = GeneratedColumn<String>(
    'company_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cmp_default'),
  );
  static const VerificationMeta _voucherNumberMeta = const VerificationMeta(
    'voucherNumber',
  );
  @override
  late final GeneratedColumn<String> voucherNumber = GeneratedColumn<String>(
    'voucher_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partyIdMeta = const VerificationMeta(
    'partyId',
  );
  @override
  late final GeneratedColumn<String> partyId = GeneratedColumn<String>(
    'party_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partyNameMeta = const VerificationMeta(
    'partyName',
  );
  @override
  late final GeneratedColumn<String> partyName = GeneratedColumn<String>(
    'party_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('posted'),
  );
  static const VerificationMeta _paymentModeMeta = const VerificationMeta(
    'paymentMode',
  );
  @override
  late final GeneratedColumn<String> paymentMode = GeneratedColumn<String>(
    'payment_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('cash'),
  );
  static const VerificationMeta _subtotalInCentsMeta = const VerificationMeta(
    'subtotalInCents',
  );
  @override
  late final GeneratedColumn<int> subtotalInCents = GeneratedColumn<int>(
    'subtotal_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _taxInCentsMeta = const VerificationMeta(
    'taxInCents',
  );
  @override
  late final GeneratedColumn<int> taxInCents = GeneratedColumn<int>(
    'tax_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _discountInCentsMeta = const VerificationMeta(
    'discountInCents',
  );
  @override
  late final GeneratedColumn<int> discountInCents = GeneratedColumn<int>(
    'discount_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalAmountInCentsMeta =
      const VerificationMeta('totalAmountInCents');
  @override
  late final GeneratedColumn<int> totalAmountInCents = GeneratedColumn<int>(
    'total_amount_in_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _narrationMeta = const VerificationMeta(
    'narration',
  );
  @override
  late final GeneratedColumn<String> narration = GeneratedColumn<String>(
    'narration',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceNumberMeta = const VerificationMeta(
    'referenceNumber',
  );
  @override
  late final GeneratedColumn<String> referenceNumber = GeneratedColumn<String>(
    'reference_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceVoucherIdMeta = const VerificationMeta(
    'sourceVoucherId',
  );
  @override
  late final GeneratedColumn<String> sourceVoucherId = GeneratedColumn<String>(
    'source_voucher_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptPhotoUrlMeta = const VerificationMeta(
    'receiptPhotoUrl',
  );
  @override
  late final GeneratedColumn<String> receiptPhotoUrl = GeneratedColumn<String>(
    'receipt_photo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _itemsJsonMeta = const VerificationMeta(
    'itemsJson',
  );
  @override
  late final GeneratedColumn<String> itemsJson = GeneratedColumn<String>(
    'items_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    voucherNumber,
    type,
    date,
    dueDate,
    partyId,
    partyName,
    status,
    paymentMode,
    subtotalInCents,
    taxInCents,
    discountInCents,
    totalAmountInCents,
    narration,
    referenceNumber,
    sourceVoucherId,
    receiptPhotoUrl,
    itemsJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vouchers';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoucherTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('voucher_number')) {
      context.handle(
        _voucherNumberMeta,
        voucherNumber.isAcceptableOrUnknown(
          data['voucher_number']!,
          _voucherNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_voucherNumberMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('party_id')) {
      context.handle(
        _partyIdMeta,
        partyId.isAcceptableOrUnknown(data['party_id']!, _partyIdMeta),
      );
    }
    if (data.containsKey('party_name')) {
      context.handle(
        _partyNameMeta,
        partyName.isAcceptableOrUnknown(data['party_name']!, _partyNameMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('payment_mode')) {
      context.handle(
        _paymentModeMeta,
        paymentMode.isAcceptableOrUnknown(
          data['payment_mode']!,
          _paymentModeMeta,
        ),
      );
    }
    if (data.containsKey('subtotal_in_cents')) {
      context.handle(
        _subtotalInCentsMeta,
        subtotalInCents.isAcceptableOrUnknown(
          data['subtotal_in_cents']!,
          _subtotalInCentsMeta,
        ),
      );
    }
    if (data.containsKey('tax_in_cents')) {
      context.handle(
        _taxInCentsMeta,
        taxInCents.isAcceptableOrUnknown(
          data['tax_in_cents']!,
          _taxInCentsMeta,
        ),
      );
    }
    if (data.containsKey('discount_in_cents')) {
      context.handle(
        _discountInCentsMeta,
        discountInCents.isAcceptableOrUnknown(
          data['discount_in_cents']!,
          _discountInCentsMeta,
        ),
      );
    }
    if (data.containsKey('total_amount_in_cents')) {
      context.handle(
        _totalAmountInCentsMeta,
        totalAmountInCents.isAcceptableOrUnknown(
          data['total_amount_in_cents']!,
          _totalAmountInCentsMeta,
        ),
      );
    }
    if (data.containsKey('narration')) {
      context.handle(
        _narrationMeta,
        narration.isAcceptableOrUnknown(data['narration']!, _narrationMeta),
      );
    }
    if (data.containsKey('reference_number')) {
      context.handle(
        _referenceNumberMeta,
        referenceNumber.isAcceptableOrUnknown(
          data['reference_number']!,
          _referenceNumberMeta,
        ),
      );
    }
    if (data.containsKey('source_voucher_id')) {
      context.handle(
        _sourceVoucherIdMeta,
        sourceVoucherId.isAcceptableOrUnknown(
          data['source_voucher_id']!,
          _sourceVoucherIdMeta,
        ),
      );
    }
    if (data.containsKey('receipt_photo_url')) {
      context.handle(
        _receiptPhotoUrlMeta,
        receiptPhotoUrl.isAcceptableOrUnknown(
          data['receipt_photo_url']!,
          _receiptPhotoUrlMeta,
        ),
      );
    }
    if (data.containsKey('items_json')) {
      context.handle(
        _itemsJsonMeta,
        itemsJson.isAcceptableOrUnknown(data['items_json']!, _itemsJsonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoucherTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoucherTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}company_id'],
      )!,
      voucherNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}voucher_number'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      partyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}party_id'],
      ),
      partyName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}party_name'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      paymentMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_mode'],
      )!,
      subtotalInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtotal_in_cents'],
      )!,
      taxInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_in_cents'],
      )!,
      discountInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}discount_in_cents'],
      )!,
      totalAmountInCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_amount_in_cents'],
      )!,
      narration: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}narration'],
      ),
      referenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_number'],
      ),
      sourceVoucherId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_voucher_id'],
      ),
      receiptPhotoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_photo_url'],
      ),
      itemsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}items_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $VouchersTable createAlias(String alias) {
    return $VouchersTable(attachedDatabase, alias);
  }
}

class VoucherTableData extends DataClass
    implements Insertable<VoucherTableData> {
  final String id;
  final String companyId;
  final String voucherNumber;
  final String type;
  final DateTime date;
  final DateTime? dueDate;
  final String? partyId;
  final String? partyName;
  final String status;
  final String paymentMode;
  final int subtotalInCents;
  final int taxInCents;
  final int discountInCents;
  final int totalAmountInCents;
  final String? narration;
  final String? referenceNumber;
  final String? sourceVoucherId;
  final String? receiptPhotoUrl;
  final String? itemsJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const VoucherTableData({
    required this.id,
    required this.companyId,
    required this.voucherNumber,
    required this.type,
    required this.date,
    this.dueDate,
    this.partyId,
    this.partyName,
    required this.status,
    required this.paymentMode,
    required this.subtotalInCents,
    required this.taxInCents,
    required this.discountInCents,
    required this.totalAmountInCents,
    this.narration,
    this.referenceNumber,
    this.sourceVoucherId,
    this.receiptPhotoUrl,
    this.itemsJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['company_id'] = Variable<String>(companyId);
    map['voucher_number'] = Variable<String>(voucherNumber);
    map['type'] = Variable<String>(type);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    if (!nullToAbsent || partyId != null) {
      map['party_id'] = Variable<String>(partyId);
    }
    if (!nullToAbsent || partyName != null) {
      map['party_name'] = Variable<String>(partyName);
    }
    map['status'] = Variable<String>(status);
    map['payment_mode'] = Variable<String>(paymentMode);
    map['subtotal_in_cents'] = Variable<int>(subtotalInCents);
    map['tax_in_cents'] = Variable<int>(taxInCents);
    map['discount_in_cents'] = Variable<int>(discountInCents);
    map['total_amount_in_cents'] = Variable<int>(totalAmountInCents);
    if (!nullToAbsent || narration != null) {
      map['narration'] = Variable<String>(narration);
    }
    if (!nullToAbsent || referenceNumber != null) {
      map['reference_number'] = Variable<String>(referenceNumber);
    }
    if (!nullToAbsent || sourceVoucherId != null) {
      map['source_voucher_id'] = Variable<String>(sourceVoucherId);
    }
    if (!nullToAbsent || receiptPhotoUrl != null) {
      map['receipt_photo_url'] = Variable<String>(receiptPhotoUrl);
    }
    if (!nullToAbsent || itemsJson != null) {
      map['items_json'] = Variable<String>(itemsJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  VouchersCompanion toCompanion(bool nullToAbsent) {
    return VouchersCompanion(
      id: Value(id),
      companyId: Value(companyId),
      voucherNumber: Value(voucherNumber),
      type: Value(type),
      date: Value(date),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      partyId: partyId == null && nullToAbsent
          ? const Value.absent()
          : Value(partyId),
      partyName: partyName == null && nullToAbsent
          ? const Value.absent()
          : Value(partyName),
      status: Value(status),
      paymentMode: Value(paymentMode),
      subtotalInCents: Value(subtotalInCents),
      taxInCents: Value(taxInCents),
      discountInCents: Value(discountInCents),
      totalAmountInCents: Value(totalAmountInCents),
      narration: narration == null && nullToAbsent
          ? const Value.absent()
          : Value(narration),
      referenceNumber: referenceNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceNumber),
      sourceVoucherId: sourceVoucherId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceVoucherId),
      receiptPhotoUrl: receiptPhotoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptPhotoUrl),
      itemsJson: itemsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(itemsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory VoucherTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoucherTableData(
      id: serializer.fromJson<String>(json['id']),
      companyId: serializer.fromJson<String>(json['companyId']),
      voucherNumber: serializer.fromJson<String>(json['voucherNumber']),
      type: serializer.fromJson<String>(json['type']),
      date: serializer.fromJson<DateTime>(json['date']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      partyId: serializer.fromJson<String?>(json['partyId']),
      partyName: serializer.fromJson<String?>(json['partyName']),
      status: serializer.fromJson<String>(json['status']),
      paymentMode: serializer.fromJson<String>(json['paymentMode']),
      subtotalInCents: serializer.fromJson<int>(json['subtotalInCents']),
      taxInCents: serializer.fromJson<int>(json['taxInCents']),
      discountInCents: serializer.fromJson<int>(json['discountInCents']),
      totalAmountInCents: serializer.fromJson<int>(json['totalAmountInCents']),
      narration: serializer.fromJson<String?>(json['narration']),
      referenceNumber: serializer.fromJson<String?>(json['referenceNumber']),
      sourceVoucherId: serializer.fromJson<String?>(json['sourceVoucherId']),
      receiptPhotoUrl: serializer.fromJson<String?>(json['receiptPhotoUrl']),
      itemsJson: serializer.fromJson<String?>(json['itemsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'companyId': serializer.toJson<String>(companyId),
      'voucherNumber': serializer.toJson<String>(voucherNumber),
      'type': serializer.toJson<String>(type),
      'date': serializer.toJson<DateTime>(date),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'partyId': serializer.toJson<String?>(partyId),
      'partyName': serializer.toJson<String?>(partyName),
      'status': serializer.toJson<String>(status),
      'paymentMode': serializer.toJson<String>(paymentMode),
      'subtotalInCents': serializer.toJson<int>(subtotalInCents),
      'taxInCents': serializer.toJson<int>(taxInCents),
      'discountInCents': serializer.toJson<int>(discountInCents),
      'totalAmountInCents': serializer.toJson<int>(totalAmountInCents),
      'narration': serializer.toJson<String?>(narration),
      'referenceNumber': serializer.toJson<String?>(referenceNumber),
      'sourceVoucherId': serializer.toJson<String?>(sourceVoucherId),
      'receiptPhotoUrl': serializer.toJson<String?>(receiptPhotoUrl),
      'itemsJson': serializer.toJson<String?>(itemsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  VoucherTableData copyWith({
    String? id,
    String? companyId,
    String? voucherNumber,
    String? type,
    DateTime? date,
    Value<DateTime?> dueDate = const Value.absent(),
    Value<String?> partyId = const Value.absent(),
    Value<String?> partyName = const Value.absent(),
    String? status,
    String? paymentMode,
    int? subtotalInCents,
    int? taxInCents,
    int? discountInCents,
    int? totalAmountInCents,
    Value<String?> narration = const Value.absent(),
    Value<String?> referenceNumber = const Value.absent(),
    Value<String?> sourceVoucherId = const Value.absent(),
    Value<String?> receiptPhotoUrl = const Value.absent(),
    Value<String?> itemsJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => VoucherTableData(
    id: id ?? this.id,
    companyId: companyId ?? this.companyId,
    voucherNumber: voucherNumber ?? this.voucherNumber,
    type: type ?? this.type,
    date: date ?? this.date,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    partyId: partyId.present ? partyId.value : this.partyId,
    partyName: partyName.present ? partyName.value : this.partyName,
    status: status ?? this.status,
    paymentMode: paymentMode ?? this.paymentMode,
    subtotalInCents: subtotalInCents ?? this.subtotalInCents,
    taxInCents: taxInCents ?? this.taxInCents,
    discountInCents: discountInCents ?? this.discountInCents,
    totalAmountInCents: totalAmountInCents ?? this.totalAmountInCents,
    narration: narration.present ? narration.value : this.narration,
    referenceNumber: referenceNumber.present
        ? referenceNumber.value
        : this.referenceNumber,
    sourceVoucherId: sourceVoucherId.present
        ? sourceVoucherId.value
        : this.sourceVoucherId,
    receiptPhotoUrl: receiptPhotoUrl.present
        ? receiptPhotoUrl.value
        : this.receiptPhotoUrl,
    itemsJson: itemsJson.present ? itemsJson.value : this.itemsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  VoucherTableData copyWithCompanion(VouchersCompanion data) {
    return VoucherTableData(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      voucherNumber: data.voucherNumber.present
          ? data.voucherNumber.value
          : this.voucherNumber,
      type: data.type.present ? data.type.value : this.type,
      date: data.date.present ? data.date.value : this.date,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      partyId: data.partyId.present ? data.partyId.value : this.partyId,
      partyName: data.partyName.present ? data.partyName.value : this.partyName,
      status: data.status.present ? data.status.value : this.status,
      paymentMode: data.paymentMode.present
          ? data.paymentMode.value
          : this.paymentMode,
      subtotalInCents: data.subtotalInCents.present
          ? data.subtotalInCents.value
          : this.subtotalInCents,
      taxInCents: data.taxInCents.present
          ? data.taxInCents.value
          : this.taxInCents,
      discountInCents: data.discountInCents.present
          ? data.discountInCents.value
          : this.discountInCents,
      totalAmountInCents: data.totalAmountInCents.present
          ? data.totalAmountInCents.value
          : this.totalAmountInCents,
      narration: data.narration.present ? data.narration.value : this.narration,
      referenceNumber: data.referenceNumber.present
          ? data.referenceNumber.value
          : this.referenceNumber,
      sourceVoucherId: data.sourceVoucherId.present
          ? data.sourceVoucherId.value
          : this.sourceVoucherId,
      receiptPhotoUrl: data.receiptPhotoUrl.present
          ? data.receiptPhotoUrl.value
          : this.receiptPhotoUrl,
      itemsJson: data.itemsJson.present ? data.itemsJson.value : this.itemsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoucherTableData(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('voucherNumber: $voucherNumber, ')
          ..write('type: $type, ')
          ..write('date: $date, ')
          ..write('dueDate: $dueDate, ')
          ..write('partyId: $partyId, ')
          ..write('partyName: $partyName, ')
          ..write('status: $status, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('subtotalInCents: $subtotalInCents, ')
          ..write('taxInCents: $taxInCents, ')
          ..write('discountInCents: $discountInCents, ')
          ..write('totalAmountInCents: $totalAmountInCents, ')
          ..write('narration: $narration, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('sourceVoucherId: $sourceVoucherId, ')
          ..write('receiptPhotoUrl: $receiptPhotoUrl, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    companyId,
    voucherNumber,
    type,
    date,
    dueDate,
    partyId,
    partyName,
    status,
    paymentMode,
    subtotalInCents,
    taxInCents,
    discountInCents,
    totalAmountInCents,
    narration,
    referenceNumber,
    sourceVoucherId,
    receiptPhotoUrl,
    itemsJson,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoucherTableData &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.voucherNumber == this.voucherNumber &&
          other.type == this.type &&
          other.date == this.date &&
          other.dueDate == this.dueDate &&
          other.partyId == this.partyId &&
          other.partyName == this.partyName &&
          other.status == this.status &&
          other.paymentMode == this.paymentMode &&
          other.subtotalInCents == this.subtotalInCents &&
          other.taxInCents == this.taxInCents &&
          other.discountInCents == this.discountInCents &&
          other.totalAmountInCents == this.totalAmountInCents &&
          other.narration == this.narration &&
          other.referenceNumber == this.referenceNumber &&
          other.sourceVoucherId == this.sourceVoucherId &&
          other.receiptPhotoUrl == this.receiptPhotoUrl &&
          other.itemsJson == this.itemsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class VouchersCompanion extends UpdateCompanion<VoucherTableData> {
  final Value<String> id;
  final Value<String> companyId;
  final Value<String> voucherNumber;
  final Value<String> type;
  final Value<DateTime> date;
  final Value<DateTime?> dueDate;
  final Value<String?> partyId;
  final Value<String?> partyName;
  final Value<String> status;
  final Value<String> paymentMode;
  final Value<int> subtotalInCents;
  final Value<int> taxInCents;
  final Value<int> discountInCents;
  final Value<int> totalAmountInCents;
  final Value<String?> narration;
  final Value<String?> referenceNumber;
  final Value<String?> sourceVoucherId;
  final Value<String?> receiptPhotoUrl;
  final Value<String?> itemsJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const VouchersCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.voucherNumber = const Value.absent(),
    this.type = const Value.absent(),
    this.date = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.partyId = const Value.absent(),
    this.partyName = const Value.absent(),
    this.status = const Value.absent(),
    this.paymentMode = const Value.absent(),
    this.subtotalInCents = const Value.absent(),
    this.taxInCents = const Value.absent(),
    this.discountInCents = const Value.absent(),
    this.totalAmountInCents = const Value.absent(),
    this.narration = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.sourceVoucherId = const Value.absent(),
    this.receiptPhotoUrl = const Value.absent(),
    this.itemsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VouchersCompanion.insert({
    required String id,
    this.companyId = const Value.absent(),
    required String voucherNumber,
    required String type,
    required DateTime date,
    this.dueDate = const Value.absent(),
    this.partyId = const Value.absent(),
    this.partyName = const Value.absent(),
    this.status = const Value.absent(),
    this.paymentMode = const Value.absent(),
    this.subtotalInCents = const Value.absent(),
    this.taxInCents = const Value.absent(),
    this.discountInCents = const Value.absent(),
    this.totalAmountInCents = const Value.absent(),
    this.narration = const Value.absent(),
    this.referenceNumber = const Value.absent(),
    this.sourceVoucherId = const Value.absent(),
    this.receiptPhotoUrl = const Value.absent(),
    this.itemsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       voucherNumber = Value(voucherNumber),
       type = Value(type),
       date = Value(date);
  static Insertable<VoucherTableData> custom({
    Expression<String>? id,
    Expression<String>? companyId,
    Expression<String>? voucherNumber,
    Expression<String>? type,
    Expression<DateTime>? date,
    Expression<DateTime>? dueDate,
    Expression<String>? partyId,
    Expression<String>? partyName,
    Expression<String>? status,
    Expression<String>? paymentMode,
    Expression<int>? subtotalInCents,
    Expression<int>? taxInCents,
    Expression<int>? discountInCents,
    Expression<int>? totalAmountInCents,
    Expression<String>? narration,
    Expression<String>? referenceNumber,
    Expression<String>? sourceVoucherId,
    Expression<String>? receiptPhotoUrl,
    Expression<String>? itemsJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (voucherNumber != null) 'voucher_number': voucherNumber,
      if (type != null) 'type': type,
      if (date != null) 'date': date,
      if (dueDate != null) 'due_date': dueDate,
      if (partyId != null) 'party_id': partyId,
      if (partyName != null) 'party_name': partyName,
      if (status != null) 'status': status,
      if (paymentMode != null) 'payment_mode': paymentMode,
      if (subtotalInCents != null) 'subtotal_in_cents': subtotalInCents,
      if (taxInCents != null) 'tax_in_cents': taxInCents,
      if (discountInCents != null) 'discount_in_cents': discountInCents,
      if (totalAmountInCents != null)
        'total_amount_in_cents': totalAmountInCents,
      if (narration != null) 'narration': narration,
      if (referenceNumber != null) 'reference_number': referenceNumber,
      if (sourceVoucherId != null) 'source_voucher_id': sourceVoucherId,
      if (receiptPhotoUrl != null) 'receipt_photo_url': receiptPhotoUrl,
      if (itemsJson != null) 'items_json': itemsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VouchersCompanion copyWith({
    Value<String>? id,
    Value<String>? companyId,
    Value<String>? voucherNumber,
    Value<String>? type,
    Value<DateTime>? date,
    Value<DateTime?>? dueDate,
    Value<String?>? partyId,
    Value<String?>? partyName,
    Value<String>? status,
    Value<String>? paymentMode,
    Value<int>? subtotalInCents,
    Value<int>? taxInCents,
    Value<int>? discountInCents,
    Value<int>? totalAmountInCents,
    Value<String?>? narration,
    Value<String?>? referenceNumber,
    Value<String?>? sourceVoucherId,
    Value<String?>? receiptPhotoUrl,
    Value<String?>? itemsJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return VouchersCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      type: type ?? this.type,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      partyId: partyId ?? this.partyId,
      partyName: partyName ?? this.partyName,
      status: status ?? this.status,
      paymentMode: paymentMode ?? this.paymentMode,
      subtotalInCents: subtotalInCents ?? this.subtotalInCents,
      taxInCents: taxInCents ?? this.taxInCents,
      discountInCents: discountInCents ?? this.discountInCents,
      totalAmountInCents: totalAmountInCents ?? this.totalAmountInCents,
      narration: narration ?? this.narration,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      sourceVoucherId: sourceVoucherId ?? this.sourceVoucherId,
      receiptPhotoUrl: receiptPhotoUrl ?? this.receiptPhotoUrl,
      itemsJson: itemsJson ?? this.itemsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<String>(companyId.value);
    }
    if (voucherNumber.present) {
      map['voucher_number'] = Variable<String>(voucherNumber.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (partyId.present) {
      map['party_id'] = Variable<String>(partyId.value);
    }
    if (partyName.present) {
      map['party_name'] = Variable<String>(partyName.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (paymentMode.present) {
      map['payment_mode'] = Variable<String>(paymentMode.value);
    }
    if (subtotalInCents.present) {
      map['subtotal_in_cents'] = Variable<int>(subtotalInCents.value);
    }
    if (taxInCents.present) {
      map['tax_in_cents'] = Variable<int>(taxInCents.value);
    }
    if (discountInCents.present) {
      map['discount_in_cents'] = Variable<int>(discountInCents.value);
    }
    if (totalAmountInCents.present) {
      map['total_amount_in_cents'] = Variable<int>(totalAmountInCents.value);
    }
    if (narration.present) {
      map['narration'] = Variable<String>(narration.value);
    }
    if (referenceNumber.present) {
      map['reference_number'] = Variable<String>(referenceNumber.value);
    }
    if (sourceVoucherId.present) {
      map['source_voucher_id'] = Variable<String>(sourceVoucherId.value);
    }
    if (receiptPhotoUrl.present) {
      map['receipt_photo_url'] = Variable<String>(receiptPhotoUrl.value);
    }
    if (itemsJson.present) {
      map['items_json'] = Variable<String>(itemsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VouchersCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('voucherNumber: $voucherNumber, ')
          ..write('type: $type, ')
          ..write('date: $date, ')
          ..write('dueDate: $dueDate, ')
          ..write('partyId: $partyId, ')
          ..write('partyName: $partyName, ')
          ..write('status: $status, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('subtotalInCents: $subtotalInCents, ')
          ..write('taxInCents: $taxInCents, ')
          ..write('discountInCents: $discountInCents, ')
          ..write('totalAmountInCents: $totalAmountInCents, ')
          ..write('narration: $narration, ')
          ..write('referenceNumber: $referenceNumber, ')
          ..write('sourceVoucherId: $sourceVoucherId, ')
          ..write('receiptPhotoUrl: $receiptPhotoUrl, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CompaniesTable companies = $CompaniesTable(this);
  late final $PartiesTable parties = $PartiesTable(this);
  late final $LedgerEntriesTable ledgerEntries = $LedgerEntriesTable(this);
  late final $AuditLogsTable auditLogs = $AuditLogsTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $InventoryItemsTable inventoryItems = $InventoryItemsTable(this);
  late final $StockLedgerTable stockLedger = $StockLedgerTable(this);
  late final $VouchersTable vouchers = $VouchersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    companies,
    parties,
    ledgerEntries,
    auditLogs,
    syncOutbox,
    inventoryItems,
    stockLedger,
    vouchers,
  ];
}

typedef $$CompaniesTableCreateCompanionBuilder =
    CompaniesCompanion Function({
      required String id,
      required String name,
      required String legalName,
      Value<String?> gstin,
      Value<String> currencyCode,
      Value<String?> address,
      Value<String?> email,
      Value<String?> phoneNumber,
      Value<bool> isCloudSyncEnabled,
      Value<bool> isDropboxSyncEnabled,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$CompaniesTableUpdateCompanionBuilder =
    CompaniesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> legalName,
      Value<String?> gstin,
      Value<String> currencyCode,
      Value<String?> address,
      Value<String?> email,
      Value<String?> phoneNumber,
      Value<bool> isCloudSyncEnabled,
      Value<bool> isDropboxSyncEnabled,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CompaniesTableFilterComposer
    extends Composer<_$AppDatabase, $CompaniesTable> {
  $$CompaniesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legalName => $composableBuilder(
    column: $table.legalName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gstin => $composableBuilder(
    column: $table.gstin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isCloudSyncEnabled => $composableBuilder(
    column: $table.isCloudSyncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDropboxSyncEnabled => $composableBuilder(
    column: $table.isDropboxSyncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CompaniesTableOrderingComposer
    extends Composer<_$AppDatabase, $CompaniesTable> {
  $$CompaniesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legalName => $composableBuilder(
    column: $table.legalName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gstin => $composableBuilder(
    column: $table.gstin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isCloudSyncEnabled => $composableBuilder(
    column: $table.isCloudSyncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDropboxSyncEnabled => $composableBuilder(
    column: $table.isDropboxSyncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CompaniesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CompaniesTable> {
  $$CompaniesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get legalName =>
      $composableBuilder(column: $table.legalName, builder: (column) => column);

  GeneratedColumn<String> get gstin =>
      $composableBuilder(column: $table.gstin, builder: (column) => column);

  GeneratedColumn<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isCloudSyncEnabled => $composableBuilder(
    column: $table.isCloudSyncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDropboxSyncEnabled => $composableBuilder(
    column: $table.isDropboxSyncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CompaniesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CompaniesTable,
          CompanyTableData,
          $$CompaniesTableFilterComposer,
          $$CompaniesTableOrderingComposer,
          $$CompaniesTableAnnotationComposer,
          $$CompaniesTableCreateCompanionBuilder,
          $$CompaniesTableUpdateCompanionBuilder,
          (
            CompanyTableData,
            BaseReferences<_$AppDatabase, $CompaniesTable, CompanyTableData>,
          ),
          CompanyTableData,
          PrefetchHooks Function()
        > {
  $$CompaniesTableTableManager(_$AppDatabase db, $CompaniesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CompaniesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CompaniesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CompaniesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> legalName = const Value.absent(),
                Value<String?> gstin = const Value.absent(),
                Value<String> currencyCode = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> phoneNumber = const Value.absent(),
                Value<bool> isCloudSyncEnabled = const Value.absent(),
                Value<bool> isDropboxSyncEnabled = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompaniesCompanion(
                id: id,
                name: name,
                legalName: legalName,
                gstin: gstin,
                currencyCode: currencyCode,
                address: address,
                email: email,
                phoneNumber: phoneNumber,
                isCloudSyncEnabled: isCloudSyncEnabled,
                isDropboxSyncEnabled: isDropboxSyncEnabled,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String legalName,
                Value<String?> gstin = const Value.absent(),
                Value<String> currencyCode = const Value.absent(),
                Value<String?> address = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<String?> phoneNumber = const Value.absent(),
                Value<bool> isCloudSyncEnabled = const Value.absent(),
                Value<bool> isDropboxSyncEnabled = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompaniesCompanion.insert(
                id: id,
                name: name,
                legalName: legalName,
                gstin: gstin,
                currencyCode: currencyCode,
                address: address,
                email: email,
                phoneNumber: phoneNumber,
                isCloudSyncEnabled: isCloudSyncEnabled,
                isDropboxSyncEnabled: isDropboxSyncEnabled,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CompaniesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CompaniesTable,
      CompanyTableData,
      $$CompaniesTableFilterComposer,
      $$CompaniesTableOrderingComposer,
      $$CompaniesTableAnnotationComposer,
      $$CompaniesTableCreateCompanionBuilder,
      $$CompaniesTableUpdateCompanionBuilder,
      (
        CompanyTableData,
        BaseReferences<_$AppDatabase, $CompaniesTable, CompanyTableData>,
      ),
      CompanyTableData,
      PrefetchHooks Function()
    >;
typedef $$PartiesTableCreateCompanionBuilder =
    PartiesCompanion Function({
      required String id,
      Value<String> companyId,
      required String name,
      required String phoneNumber,
      required PartyType type,
      Value<int> netBalanceInCents,
      required DateTime lastUpdated,
      Value<bool> isDeleted,
      Value<int> rowid,
    });
typedef $$PartiesTableUpdateCompanionBuilder =
    PartiesCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> name,
      Value<String> phoneNumber,
      Value<PartyType> type,
      Value<int> netBalanceInCents,
      Value<DateTime> lastUpdated,
      Value<bool> isDeleted,
      Value<int> rowid,
    });

final class $$PartiesTableReferences
    extends BaseReferences<_$AppDatabase, $PartiesTable, PartyTableData> {
  $$PartiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LedgerEntriesTable, List<LedgerEntryTableData>>
  _ledgerEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ledgerEntries,
    aliasName: 'parties__id__ledger_entries__party_id',
  );

  $$LedgerEntriesTableProcessedTableManager get ledgerEntriesRefs {
    final manager = $$LedgerEntriesTableTableManager(
      $_db,
      $_db.ledgerEntries,
    ).filter((f) => f.partyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ledgerEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PartiesTableFilterComposer
    extends Composer<_$AppDatabase, $PartiesTable> {
  $$PartiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PartyType, PartyType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get netBalanceInCents => $composableBuilder(
    column: $table.netBalanceInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> ledgerEntriesRefs(
    Expression<bool> Function($$LedgerEntriesTableFilterComposer f) f,
  ) {
    final $$LedgerEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ledgerEntries,
      getReferencedColumn: (t) => t.partyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LedgerEntriesTableFilterComposer(
            $db: $db,
            $table: $db.ledgerEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PartiesTableOrderingComposer
    extends Composer<_$AppDatabase, $PartiesTable> {
  $$PartiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get netBalanceInCents => $composableBuilder(
    column: $table.netBalanceInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
    column: $table.isDeleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PartiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PartiesTable> {
  $$PartiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phoneNumber => $composableBuilder(
    column: $table.phoneNumber,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PartyType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get netBalanceInCents => $composableBuilder(
    column: $table.netBalanceInCents,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  Expression<T> ledgerEntriesRefs<T extends Object>(
    Expression<T> Function($$LedgerEntriesTableAnnotationComposer a) f,
  ) {
    final $$LedgerEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ledgerEntries,
      getReferencedColumn: (t) => t.partyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LedgerEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.ledgerEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PartiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PartiesTable,
          PartyTableData,
          $$PartiesTableFilterComposer,
          $$PartiesTableOrderingComposer,
          $$PartiesTableAnnotationComposer,
          $$PartiesTableCreateCompanionBuilder,
          $$PartiesTableUpdateCompanionBuilder,
          (PartyTableData, $$PartiesTableReferences),
          PartyTableData,
          PrefetchHooks Function({bool ledgerEntriesRefs})
        > {
  $$PartiesTableTableManager(_$AppDatabase db, $PartiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PartiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PartiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PartiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> phoneNumber = const Value.absent(),
                Value<PartyType> type = const Value.absent(),
                Value<int> netBalanceInCents = const Value.absent(),
                Value<DateTime> lastUpdated = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PartiesCompanion(
                id: id,
                companyId: companyId,
                name: name,
                phoneNumber: phoneNumber,
                type: type,
                netBalanceInCents: netBalanceInCents,
                lastUpdated: lastUpdated,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> companyId = const Value.absent(),
                required String name,
                required String phoneNumber,
                required PartyType type,
                Value<int> netBalanceInCents = const Value.absent(),
                required DateTime lastUpdated,
                Value<bool> isDeleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PartiesCompanion.insert(
                id: id,
                companyId: companyId,
                name: name,
                phoneNumber: phoneNumber,
                type: type,
                netBalanceInCents: netBalanceInCents,
                lastUpdated: lastUpdated,
                isDeleted: isDeleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PartiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({ledgerEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (ledgerEntriesRefs) db.ledgerEntries,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (ledgerEntriesRefs)
                    await $_getPrefetchedData<
                      PartyTableData,
                      $PartiesTable,
                      LedgerEntryTableData
                    >(
                      currentTable: table,
                      referencedTable: $$PartiesTableReferences
                          ._ledgerEntriesRefsTable(db),
                      managerFromTypedResult: (p0) => $$PartiesTableReferences(
                        db,
                        table,
                        p0,
                      ).ledgerEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.partyId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PartiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PartiesTable,
      PartyTableData,
      $$PartiesTableFilterComposer,
      $$PartiesTableOrderingComposer,
      $$PartiesTableAnnotationComposer,
      $$PartiesTableCreateCompanionBuilder,
      $$PartiesTableUpdateCompanionBuilder,
      (PartyTableData, $$PartiesTableReferences),
      PartyTableData,
      PrefetchHooks Function({bool ledgerEntriesRefs})
    >;
typedef $$LedgerEntriesTableCreateCompanionBuilder =
    LedgerEntriesCompanion Function({
      required String id,
      Value<String> companyId,
      required String partyId,
      required int amountInCents,
      required EntryType type,
      required DateTime date,
      Value<String?> note,
      Value<String?> receiptPhotoUrl,
      Value<bool> isVoided,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$LedgerEntriesTableUpdateCompanionBuilder =
    LedgerEntriesCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> partyId,
      Value<int> amountInCents,
      Value<EntryType> type,
      Value<DateTime> date,
      Value<String?> note,
      Value<String?> receiptPhotoUrl,
      Value<bool> isVoided,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$LedgerEntriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $LedgerEntriesTable,
          LedgerEntryTableData
        > {
  $$LedgerEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PartiesTable _partyIdTable(_$AppDatabase db) =>
      db.parties.createAlias('ledger_entries__party_id__parties__id');

  $$PartiesTableProcessedTableManager get partyId {
    final $_column = $_itemColumn<String>('party_id')!;

    final manager = $$PartiesTableTableManager(
      $_db,
      $_db.parties,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_partyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LedgerEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountInCents => $composableBuilder(
    column: $table.amountInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<EntryType, EntryType, String> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptPhotoUrl => $composableBuilder(
    column: $table.receiptPhotoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVoided => $composableBuilder(
    column: $table.isVoided,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PartiesTableFilterComposer get partyId {
    final $$PartiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.partyId,
      referencedTable: $db.parties,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PartiesTableFilterComposer(
            $db: $db,
            $table: $db.parties,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LedgerEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountInCents => $composableBuilder(
    column: $table.amountInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptPhotoUrl => $composableBuilder(
    column: $table.receiptPhotoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVoided => $composableBuilder(
    column: $table.isVoided,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PartiesTableOrderingComposer get partyId {
    final $$PartiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.partyId,
      referencedTable: $db.parties,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PartiesTableOrderingComposer(
            $db: $db,
            $table: $db.parties,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LedgerEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<int> get amountInCents => $composableBuilder(
    column: $table.amountInCents,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<EntryType, String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get receiptPhotoUrl => $composableBuilder(
    column: $table.receiptPhotoUrl,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isVoided =>
      $composableBuilder(column: $table.isVoided, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PartiesTableAnnotationComposer get partyId {
    final $$PartiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.partyId,
      referencedTable: $db.parties,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PartiesTableAnnotationComposer(
            $db: $db,
            $table: $db.parties,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LedgerEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LedgerEntriesTable,
          LedgerEntryTableData,
          $$LedgerEntriesTableFilterComposer,
          $$LedgerEntriesTableOrderingComposer,
          $$LedgerEntriesTableAnnotationComposer,
          $$LedgerEntriesTableCreateCompanionBuilder,
          $$LedgerEntriesTableUpdateCompanionBuilder,
          (LedgerEntryTableData, $$LedgerEntriesTableReferences),
          LedgerEntryTableData,
          PrefetchHooks Function({bool partyId})
        > {
  $$LedgerEntriesTableTableManager(_$AppDatabase db, $LedgerEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> partyId = const Value.absent(),
                Value<int> amountInCents = const Value.absent(),
                Value<EntryType> type = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> receiptPhotoUrl = const Value.absent(),
                Value<bool> isVoided = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerEntriesCompanion(
                id: id,
                companyId: companyId,
                partyId: partyId,
                amountInCents: amountInCents,
                type: type,
                date: date,
                note: note,
                receiptPhotoUrl: receiptPhotoUrl,
                isVoided: isVoided,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> companyId = const Value.absent(),
                required String partyId,
                required int amountInCents,
                required EntryType type,
                required DateTime date,
                Value<String?> note = const Value.absent(),
                Value<String?> receiptPhotoUrl = const Value.absent(),
                Value<bool> isVoided = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgerEntriesCompanion.insert(
                id: id,
                companyId: companyId,
                partyId: partyId,
                amountInCents: amountInCents,
                type: type,
                date: date,
                note: note,
                receiptPhotoUrl: receiptPhotoUrl,
                isVoided: isVoided,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LedgerEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({partyId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (partyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.partyId,
                                referencedTable: $$LedgerEntriesTableReferences
                                    ._partyIdTable(db),
                                referencedColumn: $$LedgerEntriesTableReferences
                                    ._partyIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LedgerEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LedgerEntriesTable,
      LedgerEntryTableData,
      $$LedgerEntriesTableFilterComposer,
      $$LedgerEntriesTableOrderingComposer,
      $$LedgerEntriesTableAnnotationComposer,
      $$LedgerEntriesTableCreateCompanionBuilder,
      $$LedgerEntriesTableUpdateCompanionBuilder,
      (LedgerEntryTableData, $$LedgerEntriesTableReferences),
      LedgerEntryTableData,
      PrefetchHooks Function({bool partyId})
    >;
typedef $$AuditLogsTableCreateCompanionBuilder =
    AuditLogsCompanion Function({
      required String id,
      required String companyId,
      required String userId,
      required String entityType,
      required String entityId,
      required String action,
      required DateTime timestamp,
      Value<String?> oldStateJson,
      Value<String?> newStateJson,
      Value<String?> diffJson,
      required String checksum,
      Value<String?> previousChecksum,
      Value<int> rowid,
    });
typedef $$AuditLogsTableUpdateCompanionBuilder =
    AuditLogsCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> userId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> action,
      Value<DateTime> timestamp,
      Value<String?> oldStateJson,
      Value<String?> newStateJson,
      Value<String?> diffJson,
      Value<String> checksum,
      Value<String?> previousChecksum,
      Value<int> rowid,
    });

class $$AuditLogsTableFilterComposer
    extends Composer<_$AppDatabase, $AuditLogsTable> {
  $$AuditLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oldStateJson => $composableBuilder(
    column: $table.oldStateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newStateJson => $composableBuilder(
    column: $table.newStateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diffJson => $composableBuilder(
    column: $table.diffJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousChecksum => $composableBuilder(
    column: $table.previousChecksum,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AuditLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $AuditLogsTable> {
  $$AuditLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oldStateJson => $composableBuilder(
    column: $table.oldStateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newStateJson => $composableBuilder(
    column: $table.newStateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diffJson => $composableBuilder(
    column: $table.diffJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checksum => $composableBuilder(
    column: $table.checksum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousChecksum => $composableBuilder(
    column: $table.previousChecksum,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuditLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AuditLogsTable> {
  $$AuditLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get oldStateJson => $composableBuilder(
    column: $table.oldStateJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get newStateJson => $composableBuilder(
    column: $table.newStateJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get diffJson =>
      $composableBuilder(column: $table.diffJson, builder: (column) => column);

  GeneratedColumn<String> get checksum =>
      $composableBuilder(column: $table.checksum, builder: (column) => column);

  GeneratedColumn<String> get previousChecksum => $composableBuilder(
    column: $table.previousChecksum,
    builder: (column) => column,
  );
}

class $$AuditLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AuditLogsTable,
          AuditLogTableData,
          $$AuditLogsTableFilterComposer,
          $$AuditLogsTableOrderingComposer,
          $$AuditLogsTableAnnotationComposer,
          $$AuditLogsTableCreateCompanionBuilder,
          $$AuditLogsTableUpdateCompanionBuilder,
          (
            AuditLogTableData,
            BaseReferences<_$AppDatabase, $AuditLogsTable, AuditLogTableData>,
          ),
          AuditLogTableData,
          PrefetchHooks Function()
        > {
  $$AuditLogsTableTableManager(_$AppDatabase db, $AuditLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuditLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuditLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuditLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String?> oldStateJson = const Value.absent(),
                Value<String?> newStateJson = const Value.absent(),
                Value<String?> diffJson = const Value.absent(),
                Value<String> checksum = const Value.absent(),
                Value<String?> previousChecksum = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuditLogsCompanion(
                id: id,
                companyId: companyId,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                action: action,
                timestamp: timestamp,
                oldStateJson: oldStateJson,
                newStateJson: newStateJson,
                diffJson: diffJson,
                checksum: checksum,
                previousChecksum: previousChecksum,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String companyId,
                required String userId,
                required String entityType,
                required String entityId,
                required String action,
                required DateTime timestamp,
                Value<String?> oldStateJson = const Value.absent(),
                Value<String?> newStateJson = const Value.absent(),
                Value<String?> diffJson = const Value.absent(),
                required String checksum,
                Value<String?> previousChecksum = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuditLogsCompanion.insert(
                id: id,
                companyId: companyId,
                userId: userId,
                entityType: entityType,
                entityId: entityId,
                action: action,
                timestamp: timestamp,
                oldStateJson: oldStateJson,
                newStateJson: newStateJson,
                diffJson: diffJson,
                checksum: checksum,
                previousChecksum: previousChecksum,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AuditLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AuditLogsTable,
      AuditLogTableData,
      $$AuditLogsTableFilterComposer,
      $$AuditLogsTableOrderingComposer,
      $$AuditLogsTableAnnotationComposer,
      $$AuditLogsTableCreateCompanionBuilder,
      $$AuditLogsTableUpdateCompanionBuilder,
      (
        AuditLogTableData,
        BaseReferences<_$AppDatabase, $AuditLogsTable, AuditLogTableData>,
      ),
      AuditLogTableData,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      Value<String> companyId,
      required String entityType,
      required String entityId,
      required String action,
      required String payload,
      Value<DateTime> createdAt,
      Value<String> status,
      Value<int> retryCount,
      Value<String?> lastError,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      Value<String> companyId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> action,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<String> status,
      Value<int> retryCount,
      Value<String?> lastError,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxTableData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxTableData,
            BaseReferences<
              _$AppDatabase,
              $SyncOutboxTable,
              SyncOutboxTableData
            >,
          ),
          SyncOutboxTableData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                companyId: companyId,
                entityType: entityType,
                entityId: entityId,
                action: action,
                payload: payload,
                createdAt: createdAt,
                status: status,
                retryCount: retryCount,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                required String entityType,
                required String entityId,
                required String action,
                required String payload,
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                id: id,
                companyId: companyId,
                entityType: entityType,
                entityId: entityId,
                action: action,
                payload: payload,
                createdAt: createdAt,
                status: status,
                retryCount: retryCount,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxTableData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxTableData,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxTableData>,
      ),
      SyncOutboxTableData,
      PrefetchHooks Function()
    >;
typedef $$InventoryItemsTableCreateCompanionBuilder =
    InventoryItemsCompanion Function({
      required String id,
      Value<String> companyId,
      required String sku,
      required String name,
      Value<String?> description,
      Value<String> unit,
      Value<int> purchasePriceInCents,
      Value<int> sellingPriceInCents,
      Value<double> currentStockQuantity,
      Value<double> minimumStockAlert,
      Value<String?> hsnCode,
      Value<double> taxRatePercent,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$InventoryItemsTableUpdateCompanionBuilder =
    InventoryItemsCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> sku,
      Value<String> name,
      Value<String?> description,
      Value<String> unit,
      Value<int> purchasePriceInCents,
      Value<int> sellingPriceInCents,
      Value<double> currentStockQuantity,
      Value<double> minimumStockAlert,
      Value<String?> hsnCode,
      Value<double> taxRatePercent,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$InventoryItemsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InventoryItemsTable,
          InventoryItemTableData
        > {
  $$InventoryItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$StockLedgerTable, List<StockLedgerTableData>>
  _stockLedgerRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.stockLedger,
    aliasName: 'inventory_items__id__stock_ledger__item_id',
  );

  $$StockLedgerTableProcessedTableManager get stockLedgerRefs {
    final manager = $$StockLedgerTableTableManager(
      $_db,
      $_db.stockLedger,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_stockLedgerRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$InventoryItemsTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get purchasePriceInCents => $composableBuilder(
    column: $table.purchasePriceInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sellingPriceInCents => $composableBuilder(
    column: $table.sellingPriceInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get currentStockQuantity => $composableBuilder(
    column: $table.currentStockQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minimumStockAlert => $composableBuilder(
    column: $table.minimumStockAlert,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hsnCode => $composableBuilder(
    column: $table.hsnCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get taxRatePercent => $composableBuilder(
    column: $table.taxRatePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> stockLedgerRefs(
    Expression<bool> Function($$StockLedgerTableFilterComposer f) f,
  ) {
    final $$StockLedgerTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockLedger,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockLedgerTableFilterComposer(
            $db: $db,
            $table: $db.stockLedger,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$InventoryItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get purchasePriceInCents => $composableBuilder(
    column: $table.purchasePriceInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sellingPriceInCents => $composableBuilder(
    column: $table.sellingPriceInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get currentStockQuantity => $composableBuilder(
    column: $table.currentStockQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minimumStockAlert => $composableBuilder(
    column: $table.minimumStockAlert,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hsnCode => $composableBuilder(
    column: $table.hsnCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get taxRatePercent => $composableBuilder(
    column: $table.taxRatePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InventoryItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get purchasePriceInCents => $composableBuilder(
    column: $table.purchasePriceInCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sellingPriceInCents => $composableBuilder(
    column: $table.sellingPriceInCents,
    builder: (column) => column,
  );

  GeneratedColumn<double> get currentStockQuantity => $composableBuilder(
    column: $table.currentStockQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get minimumStockAlert => $composableBuilder(
    column: $table.minimumStockAlert,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hsnCode =>
      $composableBuilder(column: $table.hsnCode, builder: (column) => column);

  GeneratedColumn<double> get taxRatePercent => $composableBuilder(
    column: $table.taxRatePercent,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> stockLedgerRefs<T extends Object>(
    Expression<T> Function($$StockLedgerTableAnnotationComposer a) f,
  ) {
    final $$StockLedgerTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stockLedger,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StockLedgerTableAnnotationComposer(
            $db: $db,
            $table: $db.stockLedger,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$InventoryItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryItemsTable,
          InventoryItemTableData,
          $$InventoryItemsTableFilterComposer,
          $$InventoryItemsTableOrderingComposer,
          $$InventoryItemsTableAnnotationComposer,
          $$InventoryItemsTableCreateCompanionBuilder,
          $$InventoryItemsTableUpdateCompanionBuilder,
          (InventoryItemTableData, $$InventoryItemsTableReferences),
          InventoryItemTableData,
          PrefetchHooks Function({bool stockLedgerRefs})
        > {
  $$InventoryItemsTableTableManager(
    _$AppDatabase db,
    $InventoryItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> sku = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<int> purchasePriceInCents = const Value.absent(),
                Value<int> sellingPriceInCents = const Value.absent(),
                Value<double> currentStockQuantity = const Value.absent(),
                Value<double> minimumStockAlert = const Value.absent(),
                Value<String?> hsnCode = const Value.absent(),
                Value<double> taxRatePercent = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryItemsCompanion(
                id: id,
                companyId: companyId,
                sku: sku,
                name: name,
                description: description,
                unit: unit,
                purchasePriceInCents: purchasePriceInCents,
                sellingPriceInCents: sellingPriceInCents,
                currentStockQuantity: currentStockQuantity,
                minimumStockAlert: minimumStockAlert,
                hsnCode: hsnCode,
                taxRatePercent: taxRatePercent,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> companyId = const Value.absent(),
                required String sku,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<int> purchasePriceInCents = const Value.absent(),
                Value<int> sellingPriceInCents = const Value.absent(),
                Value<double> currentStockQuantity = const Value.absent(),
                Value<double> minimumStockAlert = const Value.absent(),
                Value<String?> hsnCode = const Value.absent(),
                Value<double> taxRatePercent = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryItemsCompanion.insert(
                id: id,
                companyId: companyId,
                sku: sku,
                name: name,
                description: description,
                unit: unit,
                purchasePriceInCents: purchasePriceInCents,
                sellingPriceInCents: sellingPriceInCents,
                currentStockQuantity: currentStockQuantity,
                minimumStockAlert: minimumStockAlert,
                hsnCode: hsnCode,
                taxRatePercent: taxRatePercent,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InventoryItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({stockLedgerRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (stockLedgerRefs) db.stockLedger],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (stockLedgerRefs)
                    await $_getPrefetchedData<
                      InventoryItemTableData,
                      $InventoryItemsTable,
                      StockLedgerTableData
                    >(
                      currentTable: table,
                      referencedTable: $$InventoryItemsTableReferences
                          ._stockLedgerRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$InventoryItemsTableReferences(
                            db,
                            table,
                            p0,
                          ).stockLedgerRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.itemId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$InventoryItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryItemsTable,
      InventoryItemTableData,
      $$InventoryItemsTableFilterComposer,
      $$InventoryItemsTableOrderingComposer,
      $$InventoryItemsTableAnnotationComposer,
      $$InventoryItemsTableCreateCompanionBuilder,
      $$InventoryItemsTableUpdateCompanionBuilder,
      (InventoryItemTableData, $$InventoryItemsTableReferences),
      InventoryItemTableData,
      PrefetchHooks Function({bool stockLedgerRefs})
    >;
typedef $$StockLedgerTableCreateCompanionBuilder =
    StockLedgerCompanion Function({
      required String id,
      Value<String> companyId,
      required String itemId,
      Value<String?> voucherId,
      required String transactionType,
      required double quantity,
      Value<int> unitCostInCents,
      Value<int> totalCostInCents,
      Value<double> runningStockQuantity,
      required DateTime date,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$StockLedgerTableUpdateCompanionBuilder =
    StockLedgerCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> itemId,
      Value<String?> voucherId,
      Value<String> transactionType,
      Value<double> quantity,
      Value<int> unitCostInCents,
      Value<int> totalCostInCents,
      Value<double> runningStockQuantity,
      Value<DateTime> date,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$StockLedgerTableReferences
    extends
        BaseReferences<_$AppDatabase, $StockLedgerTable, StockLedgerTableData> {
  $$StockLedgerTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $InventoryItemsTable _itemIdTable(_$AppDatabase db) => db
      .inventoryItems
      .createAlias('stock_ledger__item_id__inventory_items__id');

  $$InventoryItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$InventoryItemsTableTableManager(
      $_db,
      $_db.inventoryItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StockLedgerTableFilterComposer
    extends Composer<_$AppDatabase, $StockLedgerTable> {
  $$StockLedgerTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voucherId => $composableBuilder(
    column: $table.voucherId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitCostInCents => $composableBuilder(
    column: $table.unitCostInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCostInCents => $composableBuilder(
    column: $table.totalCostInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get runningStockQuantity => $composableBuilder(
    column: $table.runningStockQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$InventoryItemsTableFilterComposer get itemId {
    final $$InventoryItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockLedgerTableOrderingComposer
    extends Composer<_$AppDatabase, $StockLedgerTable> {
  $$StockLedgerTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voucherId => $composableBuilder(
    column: $table.voucherId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitCostInCents => $composableBuilder(
    column: $table.unitCostInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCostInCents => $composableBuilder(
    column: $table.totalCostInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get runningStockQuantity => $composableBuilder(
    column: $table.runningStockQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$InventoryItemsTableOrderingComposer get itemId {
    final $$InventoryItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockLedgerTableAnnotationComposer
    extends Composer<_$AppDatabase, $StockLedgerTable> {
  $$StockLedgerTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get voucherId =>
      $composableBuilder(column: $table.voucherId, builder: (column) => column);

  GeneratedColumn<String> get transactionType => $composableBuilder(
    column: $table.transactionType,
    builder: (column) => column,
  );

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get unitCostInCents => $composableBuilder(
    column: $table.unitCostInCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalCostInCents => $composableBuilder(
    column: $table.totalCostInCents,
    builder: (column) => column,
  );

  GeneratedColumn<double> get runningStockQuantity => $composableBuilder(
    column: $table.runningStockQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$InventoryItemsTableAnnotationComposer get itemId {
    final $$InventoryItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockLedgerTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StockLedgerTable,
          StockLedgerTableData,
          $$StockLedgerTableFilterComposer,
          $$StockLedgerTableOrderingComposer,
          $$StockLedgerTableAnnotationComposer,
          $$StockLedgerTableCreateCompanionBuilder,
          $$StockLedgerTableUpdateCompanionBuilder,
          (StockLedgerTableData, $$StockLedgerTableReferences),
          StockLedgerTableData,
          PrefetchHooks Function({bool itemId})
        > {
  $$StockLedgerTableTableManager(_$AppDatabase db, $StockLedgerTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockLedgerTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockLedgerTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockLedgerTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String?> voucherId = const Value.absent(),
                Value<String> transactionType = const Value.absent(),
                Value<double> quantity = const Value.absent(),
                Value<int> unitCostInCents = const Value.absent(),
                Value<int> totalCostInCents = const Value.absent(),
                Value<double> runningStockQuantity = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockLedgerCompanion(
                id: id,
                companyId: companyId,
                itemId: itemId,
                voucherId: voucherId,
                transactionType: transactionType,
                quantity: quantity,
                unitCostInCents: unitCostInCents,
                totalCostInCents: totalCostInCents,
                runningStockQuantity: runningStockQuantity,
                date: date,
                note: note,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> companyId = const Value.absent(),
                required String itemId,
                Value<String?> voucherId = const Value.absent(),
                required String transactionType,
                required double quantity,
                Value<int> unitCostInCents = const Value.absent(),
                Value<int> totalCostInCents = const Value.absent(),
                Value<double> runningStockQuantity = const Value.absent(),
                required DateTime date,
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockLedgerCompanion.insert(
                id: id,
                companyId: companyId,
                itemId: itemId,
                voucherId: voucherId,
                transactionType: transactionType,
                quantity: quantity,
                unitCostInCents: unitCostInCents,
                totalCostInCents: totalCostInCents,
                runningStockQuantity: runningStockQuantity,
                date: date,
                note: note,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StockLedgerTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (itemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.itemId,
                                referencedTable: $$StockLedgerTableReferences
                                    ._itemIdTable(db),
                                referencedColumn: $$StockLedgerTableReferences
                                    ._itemIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StockLedgerTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StockLedgerTable,
      StockLedgerTableData,
      $$StockLedgerTableFilterComposer,
      $$StockLedgerTableOrderingComposer,
      $$StockLedgerTableAnnotationComposer,
      $$StockLedgerTableCreateCompanionBuilder,
      $$StockLedgerTableUpdateCompanionBuilder,
      (StockLedgerTableData, $$StockLedgerTableReferences),
      StockLedgerTableData,
      PrefetchHooks Function({bool itemId})
    >;
typedef $$VouchersTableCreateCompanionBuilder =
    VouchersCompanion Function({
      required String id,
      Value<String> companyId,
      required String voucherNumber,
      required String type,
      required DateTime date,
      Value<DateTime?> dueDate,
      Value<String?> partyId,
      Value<String?> partyName,
      Value<String> status,
      Value<String> paymentMode,
      Value<int> subtotalInCents,
      Value<int> taxInCents,
      Value<int> discountInCents,
      Value<int> totalAmountInCents,
      Value<String?> narration,
      Value<String?> referenceNumber,
      Value<String?> sourceVoucherId,
      Value<String?> receiptPhotoUrl,
      Value<String?> itemsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$VouchersTableUpdateCompanionBuilder =
    VouchersCompanion Function({
      Value<String> id,
      Value<String> companyId,
      Value<String> voucherNumber,
      Value<String> type,
      Value<DateTime> date,
      Value<DateTime?> dueDate,
      Value<String?> partyId,
      Value<String?> partyName,
      Value<String> status,
      Value<String> paymentMode,
      Value<int> subtotalInCents,
      Value<int> taxInCents,
      Value<int> discountInCents,
      Value<int> totalAmountInCents,
      Value<String?> narration,
      Value<String?> referenceNumber,
      Value<String?> sourceVoucherId,
      Value<String?> receiptPhotoUrl,
      Value<String?> itemsJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$VouchersTableFilterComposer
    extends Composer<_$AppDatabase, $VouchersTable> {
  $$VouchersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get voucherNumber => $composableBuilder(
    column: $table.voucherNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partyId => $composableBuilder(
    column: $table.partyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partyName => $composableBuilder(
    column: $table.partyName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtotalInCents => $composableBuilder(
    column: $table.subtotalInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxInCents => $composableBuilder(
    column: $table.taxInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discountInCents => $composableBuilder(
    column: $table.discountInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalAmountInCents => $composableBuilder(
    column: $table.totalAmountInCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get narration => $composableBuilder(
    column: $table.narration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceVoucherId => $composableBuilder(
    column: $table.sourceVoucherId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptPhotoUrl => $composableBuilder(
    column: $table.receiptPhotoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemsJson => $composableBuilder(
    column: $table.itemsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VouchersTableOrderingComposer
    extends Composer<_$AppDatabase, $VouchersTable> {
  $$VouchersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get voucherNumber => $composableBuilder(
    column: $table.voucherNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partyId => $composableBuilder(
    column: $table.partyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partyName => $composableBuilder(
    column: $table.partyName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtotalInCents => $composableBuilder(
    column: $table.subtotalInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxInCents => $composableBuilder(
    column: $table.taxInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discountInCents => $composableBuilder(
    column: $table.discountInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalAmountInCents => $composableBuilder(
    column: $table.totalAmountInCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get narration => $composableBuilder(
    column: $table.narration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceVoucherId => $composableBuilder(
    column: $table.sourceVoucherId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptPhotoUrl => $composableBuilder(
    column: $table.receiptPhotoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemsJson => $composableBuilder(
    column: $table.itemsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VouchersTableAnnotationComposer
    extends Composer<_$AppDatabase, $VouchersTable> {
  $$VouchersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<String> get voucherNumber => $composableBuilder(
    column: $table.voucherNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get partyId =>
      $composableBuilder(column: $table.partyId, builder: (column) => column);

  GeneratedColumn<String> get partyName =>
      $composableBuilder(column: $table.partyName, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subtotalInCents => $composableBuilder(
    column: $table.subtotalInCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taxInCents => $composableBuilder(
    column: $table.taxInCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discountInCents => $composableBuilder(
    column: $table.discountInCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalAmountInCents => $composableBuilder(
    column: $table.totalAmountInCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get narration =>
      $composableBuilder(column: $table.narration, builder: (column) => column);

  GeneratedColumn<String> get referenceNumber => $composableBuilder(
    column: $table.referenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceVoucherId => $composableBuilder(
    column: $table.sourceVoucherId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptPhotoUrl => $composableBuilder(
    column: $table.receiptPhotoUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemsJson =>
      $composableBuilder(column: $table.itemsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VouchersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VouchersTable,
          VoucherTableData,
          $$VouchersTableFilterComposer,
          $$VouchersTableOrderingComposer,
          $$VouchersTableAnnotationComposer,
          $$VouchersTableCreateCompanionBuilder,
          $$VouchersTableUpdateCompanionBuilder,
          (
            VoucherTableData,
            BaseReferences<_$AppDatabase, $VouchersTable, VoucherTableData>,
          ),
          VoucherTableData,
          PrefetchHooks Function()
        > {
  $$VouchersTableTableManager(_$AppDatabase db, $VouchersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VouchersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VouchersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VouchersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> companyId = const Value.absent(),
                Value<String> voucherNumber = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> partyId = const Value.absent(),
                Value<String?> partyName = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> paymentMode = const Value.absent(),
                Value<int> subtotalInCents = const Value.absent(),
                Value<int> taxInCents = const Value.absent(),
                Value<int> discountInCents = const Value.absent(),
                Value<int> totalAmountInCents = const Value.absent(),
                Value<String?> narration = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> sourceVoucherId = const Value.absent(),
                Value<String?> receiptPhotoUrl = const Value.absent(),
                Value<String?> itemsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VouchersCompanion(
                id: id,
                companyId: companyId,
                voucherNumber: voucherNumber,
                type: type,
                date: date,
                dueDate: dueDate,
                partyId: partyId,
                partyName: partyName,
                status: status,
                paymentMode: paymentMode,
                subtotalInCents: subtotalInCents,
                taxInCents: taxInCents,
                discountInCents: discountInCents,
                totalAmountInCents: totalAmountInCents,
                narration: narration,
                referenceNumber: referenceNumber,
                sourceVoucherId: sourceVoucherId,
                receiptPhotoUrl: receiptPhotoUrl,
                itemsJson: itemsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> companyId = const Value.absent(),
                required String voucherNumber,
                required String type,
                required DateTime date,
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String?> partyId = const Value.absent(),
                Value<String?> partyName = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> paymentMode = const Value.absent(),
                Value<int> subtotalInCents = const Value.absent(),
                Value<int> taxInCents = const Value.absent(),
                Value<int> discountInCents = const Value.absent(),
                Value<int> totalAmountInCents = const Value.absent(),
                Value<String?> narration = const Value.absent(),
                Value<String?> referenceNumber = const Value.absent(),
                Value<String?> sourceVoucherId = const Value.absent(),
                Value<String?> receiptPhotoUrl = const Value.absent(),
                Value<String?> itemsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VouchersCompanion.insert(
                id: id,
                companyId: companyId,
                voucherNumber: voucherNumber,
                type: type,
                date: date,
                dueDate: dueDate,
                partyId: partyId,
                partyName: partyName,
                status: status,
                paymentMode: paymentMode,
                subtotalInCents: subtotalInCents,
                taxInCents: taxInCents,
                discountInCents: discountInCents,
                totalAmountInCents: totalAmountInCents,
                narration: narration,
                referenceNumber: referenceNumber,
                sourceVoucherId: sourceVoucherId,
                receiptPhotoUrl: receiptPhotoUrl,
                itemsJson: itemsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VouchersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VouchersTable,
      VoucherTableData,
      $$VouchersTableFilterComposer,
      $$VouchersTableOrderingComposer,
      $$VouchersTableAnnotationComposer,
      $$VouchersTableCreateCompanionBuilder,
      $$VouchersTableUpdateCompanionBuilder,
      (
        VoucherTableData,
        BaseReferences<_$AppDatabase, $VouchersTable, VoucherTableData>,
      ),
      VoucherTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CompaniesTableTableManager get companies =>
      $$CompaniesTableTableManager(_db, _db.companies);
  $$PartiesTableTableManager get parties =>
      $$PartiesTableTableManager(_db, _db.parties);
  $$LedgerEntriesTableTableManager get ledgerEntries =>
      $$LedgerEntriesTableTableManager(_db, _db.ledgerEntries);
  $$AuditLogsTableTableManager get auditLogs =>
      $$AuditLogsTableTableManager(_db, _db.auditLogs);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$InventoryItemsTableTableManager get inventoryItems =>
      $$InventoryItemsTableTableManager(_db, _db.inventoryItems);
  $$StockLedgerTableTableManager get stockLedger =>
      $$StockLedgerTableTableManager(_db, _db.stockLedger);
  $$VouchersTableTableManager get vouchers =>
      $$VouchersTableTableManager(_db, _db.vouchers);
}
