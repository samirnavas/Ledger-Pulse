enum PartyType {
  customer,
  supplier;

  String get displayName {
    switch (this) {
      case PartyType.customer:
        return 'Customer';
      case PartyType.supplier:
        return 'Supplier';
    }
  }
}

class Party {
  final String id;
  final String name;
  final String phoneNumber;
  final PartyType type;
  final int netBalanceInCents; // Positive = Receivable (You will get), Negative = Payable (You owe)
  final DateTime lastUpdated;

  const Party({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.type,
    required this.netBalanceInCents,
    required this.lastUpdated,
  });

  bool get isReceivable => netBalanceInCents > 0;
  bool get isPayable => netBalanceInCents < 0;
  bool get isSettled => netBalanceInCents == 0;

  Party copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    PartyType? type,
    int? netBalanceInCents,
    DateTime? lastUpdated,
  }) {
    return Party(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      type: type ?? this.type,
      netBalanceInCents: netBalanceInCents ?? this.netBalanceInCents,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'type': type.name,
      'netBalanceInCents': netBalanceInCents,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id'] as String,
      name: map['name'] as String,
      phoneNumber: map['phoneNumber'] as String,
      type: PartyType.values.byName(map['type'] as String),
      netBalanceInCents: map['netBalanceInCents'] as int,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Party &&
        other.id == id &&
        other.name == name &&
        other.phoneNumber == phoneNumber &&
        other.type == type &&
        other.netBalanceInCents == netBalanceInCents &&
        other.lastUpdated == lastUpdated;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        phoneNumber,
        type,
        netBalanceInCents,
        lastUpdated,
      );
}
