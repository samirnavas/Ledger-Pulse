import 'dart:convert';

class JournalLineModel {
  final String id;
  final String companyId;
  final String journalId;
  final String accountId;
  final String? accountCode;
  final String? accountName;
  final String? partyId;
  final int debitInCents;
  final int creditInCents;
  final String? narration;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalLineModel({
    required this.id,
    required this.companyId,
    required this.journalId,
    required this.accountId,
    this.accountCode,
    this.accountName,
    this.partyId,
    this.debitInCents = 0,
    this.creditInCents = 0,
    this.narration,
    required this.createdAt,
    required this.updatedAt,
  });

  JournalLineModel copyWith({
    String? id,
    String? companyId,
    String? journalId,
    String? accountId,
    String? accountCode,
    String? accountName,
    String? partyId,
    int? debitInCents,
    int? creditInCents,
    String? narration,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalLineModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      journalId: journalId ?? this.journalId,
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      partyId: partyId ?? this.partyId,
      debitInCents: debitInCents ?? this.debitInCents,
      creditInCents: creditInCents ?? this.creditInCents,
      narration: narration ?? this.narration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'journalId': journalId,
      'accountId': accountId,
      'accountCode': accountCode,
      'accountName': accountName,
      'partyId': partyId,
      'debitInCents': debitInCents,
      'creditInCents': creditInCents,
      'narration': narration,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory JournalLineModel.fromMap(Map<String, dynamic> map) {
    return JournalLineModel(
      id: map['id'] as String,
      companyId: map['companyId'] as String? ?? 'cmp_default',
      journalId: map['journalId'] as String,
      accountId: map['accountId'] as String,
      accountCode: map['accountCode'] as String?,
      accountName: map['accountName'] as String?,
      partyId: map['partyId'] as String?,
      debitInCents: (map['debitInCents'] as int?) ?? 0,
      creditInCents: (map['creditInCents'] as int?) ?? 0,
      narration: map['narration'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory JournalLineModel.fromJson(String source) =>
      JournalLineModel.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class JournalModel {
  final String id;
  final String companyId;
  final String journalNumber;
  final String? voucherId;
  final DateTime date;
  final String? narration;
  final int totalAmountInCents;
  final String status; // 'posted', 'voided'
  final List<JournalLineModel> lines;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalModel({
    required this.id,
    required this.companyId,
    required this.journalNumber,
    this.voucherId,
    required this.date,
    this.narration,
    this.totalAmountInCents = 0,
    this.status = 'posted',
    this.lines = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isBalanced {
    final totalDebit = lines.fold<int>(0, (sum, line) => sum + line.debitInCents);
    final totalCredit = lines.fold<int>(0, (sum, line) => sum + line.creditInCents);
    return totalDebit == totalCredit && totalDebit > 0;
  }

  int get totalDebit => lines.fold<int>(0, (sum, line) => sum + line.debitInCents);
  int get totalCredit => lines.fold<int>(0, (sum, line) => sum + line.creditInCents);

  JournalModel copyWith({
    String? id,
    String? companyId,
    String? journalNumber,
    String? voucherId,
    DateTime? date,
    String? narration,
    int? totalAmountInCents,
    String? status,
    List<JournalLineModel>? lines,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      journalNumber: journalNumber ?? this.journalNumber,
      voucherId: voucherId ?? this.voucherId,
      date: date ?? this.date,
      narration: narration ?? this.narration,
      totalAmountInCents: totalAmountInCents ?? this.totalAmountInCents,
      status: status ?? this.status,
      lines: lines ?? this.lines,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'journalNumber': journalNumber,
      'voucherId': voucherId,
      'date': date.toIso8601String(),
      'narration': narration,
      'totalAmountInCents': totalAmountInCents,
      'status': status,
      'lines': lines.map((l) => l.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory JournalModel.fromMap(Map<String, dynamic> map) {
    return JournalModel(
      id: map['id'] as String,
      companyId: map['companyId'] as String? ?? 'cmp_default',
      journalNumber: map['journalNumber'] as String,
      voucherId: map['voucherId'] as String?,
      date: map['date'] != null
          ? DateTime.parse(map['date'] as String)
          : DateTime.now(),
      narration: map['narration'] as String?,
      totalAmountInCents: (map['totalAmountInCents'] as int?) ?? 0,
      status: (map['status'] as String?) ?? 'posted',
      lines: (map['lines'] as List<dynamic>?)
              ?.map((l) => JournalLineModel.fromMap(l as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory JournalModel.fromJson(String source) =>
      JournalModel.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
