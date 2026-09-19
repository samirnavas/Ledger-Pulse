class UserProfile {
  final String name;
  final String businessName;
  final String phoneNumber;
  final String email;
  final String address;
  final String gstin;
  final String businessType;

  const UserProfile({
    required this.name,
    required this.businessName,
    required this.phoneNumber,
    required this.email,
    required this.address,
    required this.gstin,
    required this.businessType,
  });

  UserProfile copyWith({
    String? name,
    String? businessName,
    String? phoneNumber,
    String? email,
    String? address,
    String? gstin,
    String? businessType,
  }) {
    return UserProfile(
      name: name ?? this.name,
      businessName: businessName ?? this.businessName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      gstin: gstin ?? this.gstin,
      businessType: businessType ?? this.businessType,
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return 'LP';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}
