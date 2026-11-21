import 'party_model.dart';
import '../../core/network/sync_codec.dart';

enum EntryType {
  gave, // Debit / You Gave (Receivable increase for Customer, Payable decrease for Supplier)
  got; // Credit / You Got (Receivable decrease for Customer, Payable increase for Supplier)

  String get displayName {
    switch (this) {
      case EntryType.gave:
        return 'You Gave';
      case EntryType.got:
        return 'You Got';
    }
  }

  String get shortTag {
    switch (this) {
      case EntryType.gave:
        return 'GAVE';
      case EntryType.got:
        return 'GOT';
    }
  }
}

enum LedgerEntryKind { credit, payment }

class LedgerEntry {
  static const _unchanged = Object();
  final String id;
  final String partyId;
  final int amountInCents;
  final EntryType type;
  final DateTime date;
  final String? note;
  final LedgerPaymentMethod? paymentMethod;
  final LedgerEntryKind? kind;

  bool isPaymentFor(PartyType partyType) =>
      !id.startsWith('entry_init_') &&
      (kind == null
          ? isLedgerPayment(partyType, type)
          : kind == LedgerEntryKind.payment);

  LedgerPaymentMethod? get effectivePaymentMethod =>
      paymentMethod ?? LedgerPaymentMethod.read(note);
  final String? receiptPhotoUrl;
  final int? runningBalanceInCents; // Computed for display
  final bool isVoided;

  const LedgerEntry({
    required this.id,
    required this.partyId,
    required this.amountInCents,
    required this.type,
    required this.date,
    this.note,
    this.paymentMethod,
    this.kind,
    this.receiptPhotoUrl,
    this.runningBalanceInCents,
    this.isVoided = false,
  });

  LedgerEntry copyWith({
    String? id,
    String? partyId,
    int? amountInCents,
    EntryType? type,
    DateTime? date,
    Object? note = _unchanged,
    Object? paymentMethod = _unchanged,
    Object? kind = _unchanged,
    String? receiptPhotoUrl,
    int? runningBalanceInCents,
    bool? isVoided,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      partyId: partyId ?? this.partyId,
      amountInCents: amountInCents ?? this.amountInCents,
      type: type ?? this.type,
      date: date ?? this.date,
      note: identical(note, _unchanged) ? this.note : note as String?,
      paymentMethod: identical(paymentMethod, _unchanged)
          ? this.paymentMethod
          : paymentMethod as LedgerPaymentMethod?,
      kind: identical(kind, _unchanged) ? this.kind : kind as LedgerEntryKind?,
      receiptPhotoUrl: receiptPhotoUrl ?? this.receiptPhotoUrl,
      runningBalanceInCents:
          runningBalanceInCents ?? this.runningBalanceInCents,
      isVoided: isVoided ?? this.isVoided,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'partyId': partyId,
      'amountInCents': amountInCents,
      'type': type.name,
      'date': encodeTime(date),
      'note': note,
      'paymentMethod': paymentMethod?.name,
      'kind': kind?.name,
      'receiptPhotoUrl': receiptPhotoUrl,
      'runningBalanceInCents': runningBalanceInCents,
      'isVoided': isVoided,
    };
  }

  factory LedgerEntry.fromMap(Map<String, dynamic> map) {
    return LedgerEntry(
      id: map['id'] as String,
      partyId: map['partyId'] as String,
      amountInCents: map['amountInCents'] as int,
      type: EntryType.values.byName(map['type'] as String),
      date: decodeTime(map['date']),
      note: map['note'] as String?,
      paymentMethod: LedgerPaymentMethod.fromName(
        map['paymentMethod'] as String?,
      ),
      kind: LedgerEntryKind.values
          .where((kind) => kind.name == map['kind'])
          .firstOrNull,
      receiptPhotoUrl: map['receiptPhotoUrl'] as String?,
      runningBalanceInCents: map['runningBalanceInCents'] as int?,
      isVoided: (map['isVoided'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LedgerEntry &&
        other.id == id &&
        other.partyId == partyId &&
        other.amountInCents == amountInCents &&
        other.type == type &&
        other.date == date &&
        other.note == note &&
        other.paymentMethod == paymentMethod &&
        other.kind == kind &&
        other.receiptPhotoUrl == receiptPhotoUrl &&
        other.isVoided == isVoided;
  }

  @override
  int get hashCode => Object.hash(
    id,
    partyId,
    amountInCents,
    type,
    date,
    note,
    paymentMethod,
    kind,
    receiptPhotoUrl,
    isVoided,
  );
}

bool isLedgerPayment(PartyType partyType, EntryType direction) =>
    partyType == PartyType.customer
    ? direction == EntryType.got
    : direction == EntryType.gave;

/// Recognizes the exact note prefix written by earlier ledger releases.
enum LedgerPaymentMethod {
  cash('Cash'),
  bank('Bank transfer'),
  upi('UPI'),
  cheque('Cheque');

  const LedgerPaymentMethod(this.label);
  final String label;

  static LedgerPaymentMethod? fromName(String? name) =>
      values.where((method) => method.name == name).firstOrNull;

  static LedgerPaymentMethod? read(String? note) {
    for (final method in values) {
      final line = '[Payment method: ${method.label}]';
      if (note == line || note?.startsWith('$line\n') == true) return method;
    }
    return null;
  }

  static String? strip(String? note) {
    if (read(note) == null) return note;
    final newline = note!.indexOf('\n');
    return newline < 0 ? null : note.substring(newline + 1);
  }

  String encode(String note) =>
      '[Payment method: $label]${note.isEmpty ? '' : '\n$note'}';
}
