import 'dart:async';
import '../../domain/repositories/i_auth_repository.dart';

class MockAuthRepository implements IAuthRepository {
  final _authStateController = StreamController<bool>.broadcast();
  bool _isAuthenticated = true; // Default to authenticated for instant preview, can logout/login
  String? _phoneNumber = '+91 98765 43210';
  String? _pendingPhone;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get currentPhoneNumber => _phoneNumber;

  @override
  Stream<bool> get authStateStream => _authStateController.stream;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10) {
      throw Exception('Please enter a valid 10-digit phone number');
    }
    _pendingPhone = phoneNumber;
  }

  @override
  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (otp.trim() == '123456') {
      _phoneNumber = _pendingPhone ?? phoneNumber;
      _isAuthenticated = true;
      _authStateController.add(true);
      return true;
    }
    return false;
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _isAuthenticated = false;
    _phoneNumber = null;
    _authStateController.add(false);
  }

  void dispose() {
    _authStateController.close();
  }
}
