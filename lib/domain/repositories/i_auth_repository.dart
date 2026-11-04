abstract class IAuthRepository {
  Future<void> sendOtp(String phoneNumber);
  Future<bool> verifyOtp(String phoneNumber, String otp);
  Future<bool> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required bool isCompanyAccount,
  });
  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  });
  Future<void> logout();
  Stream<bool> get authStateStream;
  bool get isAuthenticated;
  String? get currentPhoneNumber;
  String? get currentUserId;
  String? get currentSessionToken;
}
