import 'dart:async';
import '../../domain/repositories/i_auth_repository.dart';

class MockAuthRepository implements IAuthRepository {
  static const String validMockUuid = '11111111-2222-4333-8444-555555555555';
  static const String validMockJwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMTExMTExMS0yMjIyLTQzMzMtODQ0NC01NTU1NTU1NTU1NTUiLCJpYXQiOjE1MTYyMzkwMjJ9.mock_signature';

  final _authStateController = StreamController<bool>.broadcast();
  bool _isAuthenticated;
  String? _phoneNumber;
  String? _email;
  String? _userId;
  String? _sessionToken;
  String? _userName;
  String? _pendingPhone;
  bool requiresEmailConfirmationOnSignUp;

  MockAuthRepository({
    bool isAuthenticated = true,
    String? userId,
    String? email = 'demo@ledgerpulse.com',
    String? phoneNumber = '+91 98765 43210',
    String? userName = 'Demo User',
    this.requiresEmailConfirmationOnSignUp = false,
  })  : _isAuthenticated = isAuthenticated,
        _userId = userId ?? (isAuthenticated ? validMockUuid : null),
        _sessionToken = isAuthenticated ? validMockJwt : null,
        _email = email,
        _phoneNumber = phoneNumber,
        _userName = userName;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get currentPhoneNumber => _phoneNumber;

  @override
  String? get currentUserId => _isAuthenticated ? (_userId ?? validMockUuid) : null;

  @override
  String? get currentSessionToken => _isAuthenticated ? (_sessionToken ?? validMockJwt) : null;

  @override
  String? get currentUserEmail => _email ?? (_phoneNumber != null && _phoneNumber!.contains('@') ? _phoneNumber : 'demo@ledgerpulse.com');

  @override
  String? get currentUserName => _userName ?? 'Demo User';

  @override
  Stream<bool> get authStateStream => _authStateController.stream;

  void setCustomUserId(String? id) {
    _userId = id;
  }

  @override
  Future<void> sendOtp(String phoneNumber) async {
    await Future.delayed(const Duration(milliseconds: 50));
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10) {
      throw Exception('Please enter a valid 10-digit phone number');
    }
    _pendingPhone = phoneNumber;
  }

  @override
  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (otp.trim() == '123456') {
      _phoneNumber = _pendingPhone ?? phoneNumber;
      _userId ??= validMockUuid;
      _sessionToken = validMockJwt;
      _isAuthenticated = true;
      _authStateController.add(true);
      return true;
    }
    return false;
  }

  @override
  Future<SignUpResult> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _email = email;
    _userName = name;

    if (requiresEmailConfirmationOnSignUp) {
      _isAuthenticated = false;
      _sessionToken = null;
      _userId ??= validMockUuid;
      return SignUpResult(
        isSuccess: true,
        requiresEmailConfirmation: true,
        userId: _userId,
        email: email,
        message: 'Account created. Please check your email to confirm your account.',
      );
    }

    _userId ??= validMockUuid;
    _sessionToken = validMockJwt;
    _isAuthenticated = true;
    _authStateController.add(true);
    return SignUpResult(
      isSuccess: true,
      requiresEmailConfirmation: false,
      userId: _userId,
      email: email,
    );
  }

  @override
  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _email = email;
    _userId ??= validMockUuid;
    _sessionToken = validMockJwt;
    _isAuthenticated = true;
    _authStateController.add(true);
    return true;
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _isAuthenticated = false;
    _userId = null;
    _sessionToken = null;
    _phoneNumber = null;
    _email = null;
    _authStateController.add(false);
  }

  void dispose() {
    _authStateController.close();
  }
}
