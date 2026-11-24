import 'package:flutter/material.dart';

import '../../../data/models/account_model.dart';

const categoryIconPresets = <String, (String, IconData)>{
  'auto': ('Automatic', Icons.auto_awesome_rounded),
  'restaurant': ('Food & dining', Icons.restaurant_rounded),
  'shopping_cart': ('Groceries', Icons.shopping_cart_rounded),
  'directions_car': ('Transport', Icons.directions_car_rounded),
  'local_gas_station': ('Fuel', Icons.local_gas_station_rounded),
  'home': ('Housing', Icons.home_rounded),
  'lightbulb': ('Utilities', Icons.lightbulb_rounded),
  'receipt_long': ('Bills', Icons.receipt_long_rounded),
  'shopping_bag': ('Shopping', Icons.shopping_bag_rounded),
  'medical_services': ('Health', Icons.medical_services_rounded),
  'school': ('Education', Icons.school_rounded),
  'movie': ('Entertainment', Icons.movie_rounded),
  'flight': ('Travel', Icons.flight_rounded),
  'pets': ('Pets', Icons.pets_rounded),
  'redeem': ('Gifts', Icons.redeem_rounded),
  'payments': ('Income', Icons.payments_rounded),
  'trending_up': ('Investments', Icons.trending_up_rounded),
};

IconData? savedCategoryIcon(AccountModel? category) {
  final key = category?.iconName;
  return key == 'auto' ? null : categoryIconPresets[key]?.$2;
}

IconData categoryIcon(AccountModel? category) {
  final saved = savedCategoryIcon(category);
  if (saved != null) return saved;
  final name = category?.name.toLowerCase() ?? '';
  for (final (key, words) in const [
    ('restaurant', ['food', 'dining', 'restaurant']),
    ('payments', ['salary', 'income', 'wage']),
    ('directions_car', ['transport', 'travel', 'fuel']),
    ('receipt_long', ['bill', 'utility', 'electric']),
    ('shopping_bag', ['shopping', 'grocer']),
    ('trending_up', ['invest', 'dividend']),
    ('home', ['rent', 'home']),
    ('medical_services', ['health', 'medical']),
  ]) {
    if (words.any(name.contains)) return categoryIconPresets[key]!.$2;
  }
  return Icons.category_rounded;
}
