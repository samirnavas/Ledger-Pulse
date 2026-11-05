import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../domain/repositories/i_auth_repository.dart';
import 'database_providers.dart';

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) {
  return null;
});

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = SupabaseAuthRepository(prefs: prefs);
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
  final String? email;
  final String? userName;
  final bool isOtpSent;
  final bool isAuthenticated;

  const AuthState({
    this.isLoading = false,
    this.error,
    this.phoneNumber,
    this.email,
    this.userName,
    this.isOtpSent = false,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    String? phoneNumber,
    String? email,
    String? userName,
    bool? isOtpSent,
    bool? isAuthenticated,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      userName: userName ?? this.userName,
      isOtpSent: isOtpSent ?? this.isOtpSent,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  IAuthRepository get _repository => ref.read(authRepositoryProvider);
  StreamSubscription<bool>? _authSub;

  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);

    _authSub?.cancel();
    _authSub = repo.authStateStream.listen((isAuth) {
      state = state.copyWith(
        isAuthenticated: isAuth,
        phoneNumber: repo.currentPhoneNumber,
        email: repo.currentUserEmail,
        userName: repo.currentUserName,
      );
    });

    ref.onDispose(() {
      _authSub?.cancel();
    });

    return AuthState(
      isAuthenticated: repo.isAuthenticated,
      phoneNumber: repo.currentPhoneNumber,
      email: repo.currentUserEmail,
      userName: repo.currentUserName,
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

  Future<bool> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required bool isCompanyAccount,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _repository.signUpWithEmailAndPassword(
        email: email,
        password: password,
        name: name,
        isCompanyAccount: isCompanyAccount,
      );
      if (success) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          phoneNumber: email,
          email: email,
          userName: name,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to create account. Please check your info and try again.',
        );
        return false;
      }
    } on AuthException catch (e) {
      String msg = e.message;
      if (msg.toLowerCase().contains('already registered') ||
          msg.toLowerCase().contains('user already exists')) {
        msg = 'An account with this email already exists. Please sign in.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    } catch (e) {
      String msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
        msg = 'Network error: Unable to connect to Supabase. Please check your internet connection.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final success = await _repository.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (success) {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          phoneNumber: email,
          email: email,
          userName: _repository.currentUserName,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Invalid credentials. Please check your email and password.',
        );
        return false;
      }
    } on AuthException catch (e) {
      String msg = e.message;
      if (msg.toLowerCase().contains('invalid login credentials') ||
          msg.toLowerCase().contains('invalid_credentials')) {
        msg = 'Invalid email or password. Please try again.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    } catch (e) {
      String msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
        msg = 'Network error: Unable to connect to Supabase. Please check your internet connection.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      ref.read(syncEngineProvider).dispose();
      await ref.read(appDatabaseProvider).close();
    } catch (_) {}
    await _repository.logout();
    state = const AuthState(isAuthenticated: false);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
