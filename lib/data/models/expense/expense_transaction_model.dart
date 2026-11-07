import 'package:flutter/foundation.dart';

enum ExpenseTransactionType {
  expense,
  income,
  transfer;

  static ExpenseTransactionType fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'income':
        return ExpenseTransactionType.income;
      case 'transfer':
        return ExpenseTransactionType.transfer;
      case 'expense':
      default:
        return ExpenseTransactionType.expense;
    }
  }

  String toDbValue() => name;
}

@immutable
class ExpenseTransactionModel {
  final String id;
  final String profileId;
  final ExpenseTransactionType transactionType;
  final int amountInCents;
  final String walletId;
  final String? toWalletId;
  final String? categoryId;
  final DateTime transactionDate;
  final String? note;
  final String? payeeOrPayer;
  final String? referenceNumber;
  final String? receiptPhotoUrl;
  final bool isCleared;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const ExpenseTransactionModel({
    required this.id,
    required this.profileId,
    required this.transactionType,
    required this.amountInCents,
    required this.walletId,
    this.toWalletId,
    this.categoryId,
    required this.transactionDate,
    this.note,
    this.payeeOrPayer,
    this.referenceNumber,
    this.receiptPhotoUrl,
    this.isCleared = true,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  double get amount => amountInCents / 100.0;
  bool get isExpense => transactionType == ExpenseTransactionType.expense;
  bool get isIncome => transactionType == ExpenseTransactionType.income;
  bool get isTransfer => transactionType == ExpenseTransactionType.transfer;

  ExpenseTransactionModel copyWith({
    String? id,
    String? profileId,
    ExpenseTransactionType? transactionType,
    int? amountInCents,
    String? walletId,
    String? toWalletId,
    String? categoryId,
    DateTime? transactionDate,
    String? note,
    String? payeeOrPayer,
    String? referenceNumber,
    String? receiptPhotoUrl,
    bool? isCleared,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return ExpenseTransactionModel(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      transactionType: transactionType ?? this.transactionType,
      amountInCents: amountInCents ?? this.amountInCents,
      walletId: walletId ?? this.walletId,
      toWalletId: toWalletId ?? this.toWalletId,
      categoryId: categoryId ?? this.categoryId,
      transactionDate: transactionDate ?? this.transactionDate,
      note: note ?? this.note,
      payeeOrPayer: payeeOrPayer ?? this.payeeOrPayer,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      receiptPhotoUrl: receiptPhotoUrl ?? this.receiptPhotoUrl,
      isCleared: isCleared ?? this.isCleared,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

