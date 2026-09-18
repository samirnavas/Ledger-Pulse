abstract class IAuthRepository {
  Future<void> sendOtp(String phoneNumber);
  Future<bool> verifyOtp(String phoneNumber, String otp);
  Future<void> logout();
  Stream<bool> get authStateStream;
  bool get isAuthenticated;
  String? get currentPhoneNumber;
}
