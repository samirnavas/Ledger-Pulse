import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock/mock_auth_repository.dart';
import '../../domain/repositories/i_auth_repository.dart';

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final repo = MockAuthRepository();
  ref.onDispose(() {
    repo.dispose();
  });
  return repo;
});

final authStateProvider = StreamProvider<bool>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateStream;
});

class AuthState {
  final bool isLoading;
  final String? error;
  final String? phoneNumber;
  final bool isOtpSent;
  final bool isAuthenticated;

  const AuthState({
    this.isLoading = false,
    this.error,
    this.phoneNumber,
    this.isOtpSent = false,
    this.isAuthenticated = true,
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    String? phoneNumber,
    bool? isOtpSent,
    bool? isAuthenticated,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isOtpSent: isOtpSent ?? this.isOtpSent,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  IAuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);
    return AuthState(
      isAuthenticated: repo.isAuthenticated,
      phoneNumber: repo.currentPhoneNumber,
    );
  }

  Future<bool> sendOtp(String phone) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.sendOtp(phone);
      state = state.copyWith(
        isLoading: false,
        phoneNumber: phone,
        isOtpSent: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> verifyOtp(String otp) async {
    if (state.phoneNumber == null) return false;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _repository.verifyOtp(state.phoneNumber!, otp);
      if (success) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid verification code. Please use 123456.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _repository.logout();
    state = const AuthState(isAuthenticated: false);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
