class SignUpResult {
  final bool isSuccess;
  final bool requiresEmailConfirmation;
  final String? userId;
  final String? email;
  final String? message;

  const SignUpResult({
    required this.isSuccess,
    this.requiresEmailConfirmation = false,
    this.userId,
    this.email,
    this.message,
  });
}

abstract class IAuthRepository {
  Future<void> sendOtp(String phoneNumber);
  Future<bool> verifyOtp(String phoneNumber, String otp);
  Future<SignUpResult> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
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
  String? get currentUserEmail;
  String? get currentUserName;
}
