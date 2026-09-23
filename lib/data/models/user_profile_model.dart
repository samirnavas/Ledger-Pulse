import 'company_model.dart';
import 'rbac_model.dart';

class UserProfile {
  final String id;
  final String name;
  final String phoneNumber;
  final String email;
  final List<Company> companies;
  final String activeCompanyId;
  final Role role;
  final List<UserCompanyRole> companyRoles;

  UserProfile({
    this.id = 'usr_default',
    required this.name,
    required this.phoneNumber,
    required this.email,
    String? businessName,
    String? address,
    String? gstin,
    String? businessType,
    List<Company>? companies,
    String? activeCompanyId,
    this.role = Role.admin,
    this.companyRoles = const [],
  })  : activeCompanyId = activeCompanyId ?? (companies != null && companies.isNotEmpty ? companies.first.id : 'cmp_default'),
        companies = (companies != null && companies.isNotEmpty)
            ? companies
            : [
                Company(
                  id: activeCompanyId ?? 'cmp_default',
                  name: businessName ?? 'Ledger Pulse Enterprise',
                  legalName: businessName ?? 'Ledger Pulse Enterprise Pvt Ltd',
                  gstin: gstin ?? '29ABCDE1234F1ZH',
                  address: address ?? 'Suite 402, Trade Tower, Bangalore, India',
                  phoneNumber: phoneNumber,
                  email: email,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              ];

  // Backwards-compatible getters mapping to active company
  Company get activeCompany {
    if (companies.isEmpty) {
      return Company(
        id: activeCompanyId,
        name: 'Ledger Pulse Enterprise',
        legalName: 'Ledger Pulse Enterprise Pvt Ltd',
        gstin: '29ABCDE1234F1ZH',
        address: 'Suite 402, Trade Tower, Bangalore, India',
        phoneNumber: phoneNumber,
        email: email,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
    return companies.firstWhere(
      (c) => c.id == activeCompanyId,
      orElse: () => companies.first,
    );
  }

  String get businessName => activeCompany.name;
  String get address => activeCompany.address ?? '';
  String get gstin => activeCompany.gstin ?? '';
  String get businessType => 'Retail & Wholesale';

  Role roleForCompany(String companyId) {
    for (final cr in companyRoles) {
      if (cr.companyId == companyId) return cr.role;
    }
    return role;
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? businessName,
    String? phoneNumber,
    String? email,
    String? address,
    String? gstin,
    String? businessType,
    List<Company>? companies,
    String? activeCompanyId,
    Role? role,
    List<UserCompanyRole>? companyRoles,
  }) {
    List<Company> updatedCompanies = companies ?? this.companies;
    if (businessName != null || address != null || gstin != null) {
      final currentActive = activeCompany;
      final updatedActive = currentActive.copyWith(
        name: businessName ?? currentActive.name,
        legalName: businessName ?? currentActive.legalName,
        address: address ?? currentActive.address,
        gstin: gstin ?? currentActive.gstin,
        updatedAt: DateTime.now(),
      );
      if (updatedCompanies.isEmpty) {
        updatedCompanies = [updatedActive];
      } else {
        updatedCompanies = updatedCompanies
            .map((c) => c.id == updatedActive.id ? updatedActive : c)
            .toList();
      }
    }

    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      companies: updatedCompanies,
      activeCompanyId: activeCompanyId ?? this.activeCompanyId,
      role: role ?? this.role,
      companyRoles: companyRoles ?? this.companyRoles,
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return 'LP';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'email': email,
      'companies': companies.map((c) => c.toMap()).toList(),
      'activeCompanyId': activeCompanyId,
      'role': role.name,
      'companyRoles': companyRoles.map((cr) => cr.toMap()).toList(),
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final companiesList = (map['companies'] as List<dynamic>?)
            ?.map((c) => Company.fromMap(c as Map<String, dynamic>))
            .toList() ??
        [];

    final companyRolesList = (map['companyRoles'] as List<dynamic>?)
            ?.map((cr) => UserCompanyRole.fromMap(cr as Map<String, dynamic>))
            .toList() ??
        [];

    final activeCompId = map['activeCompanyId'] as String? ??
        (companiesList.isNotEmpty ? companiesList.first.id : 'cmp_default');

    return UserProfile(
      id: (map['id'] as String?) ?? 'usr_default',
      name: (map['name'] as String?) ?? 'User',
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      companies: companiesList,
      activeCompanyId: activeCompId,
      role: map['role'] != null
          ? Role.values.byName(map['role'] as String)
          : Role.admin,
      companyRoles: companyRolesList,
    );
  }
}
