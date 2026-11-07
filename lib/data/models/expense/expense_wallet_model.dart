import 'package:flutter/foundation.dart';

enum ExpenseWalletType {
  cash,
  bank,
  creditCard,
  digitalWallet,
  savings;

  static ExpenseWalletType fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'bank':
        return ExpenseWalletType.bank;
      case 'creditcard':
      case 'credit_card':
        return ExpenseWalletType.creditCard;
      case 'digitalwallet':
      case 'digital_wallet':
        return ExpenseWalletType.digitalWallet;
      case 'savings':
        return ExpenseWalletType.savings;
      case 'cash':
      default:
        return ExpenseWalletType.cash;
    }
  }

  String toDbValue() {
    switch (this) {
      case ExpenseWalletType.bank:
        return 'bank';
      case ExpenseWalletType.creditCard:
        return 'credit_card';
      case ExpenseWalletType.digitalWallet:
        return 'digital_wallet';
      case ExpenseWalletType.savings:
        return 'savings';
      case ExpenseWalletType.cash:
        return 'cash';
    }
  }
}

@immutable
class ExpenseWalletModel {
  final String id;
  final String profileId;
  final String name;
  final ExpenseWalletType walletType;
  final String currencyCode;
  final int startingBalanceInCents;
  final int currentBalanceInCents;
  final String? colorHex;
  final String? iconName;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const ExpenseWalletModel({
    required this.id,
    required this.profileId,
    required this.name,
    this.walletType = ExpenseWalletType.cash,
    this.currencyCode = 'INR',
    this.startingBalanceInCents = 0,
    this.currentBalanceInCents = 0,
    this.colorHex,
    this.iconName,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  double get currentBalance => currentBalanceInCents / 100.0;
  double get startingBalance => startingBalanceInCents / 100.0;

  ExpenseWalletModel copyWith({
    String? id,
    String? profileId,
    String? name,
    ExpenseWalletType? walletType,
    String? currencyCode,
    int? startingBalanceInCents,
    int? currentBalanceInCents,
    String? colorHex,
    String? iconName,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return ExpenseWalletModel(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      walletType: walletType ?? this.walletType,
      currencyCode: currencyCode ?? this.currencyCode,
      startingBalanceInCents:
          startingBalanceInCents ?? this.startingBalanceInCents,
      currentBalanceInCents:
          currentBalanceInCents ?? this.currentBalanceInCents,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

