import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../domain/repositories/i_auth_repository.dart';

class SupabaseAuthRepository implements IAuthRepository {
  static const String _keyUserId = 'supabase_auth_user_id';
  static const String _keySessionToken = 'supabase_auth_session_token';
  static const String _keyPhoneNumber = 'supabase_auth_phone_number';
  static const String _keyEmail = 'supabase_auth_email';
  static const String _keyUserName = 'supabase_auth_user_name';

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool isValidUuid(String? id) {
    if (id == null) return false;
    return _uuidRegex.hasMatch(id);
  }

  static bool isValidJwt(String? token) {
    if (token == null || token.isEmpty) return false;
    final parts = token.split('.');
    return parts.length == 3 && parts.every((p) => p.isNotEmpty);
  }

  final SupabaseClient? _client;
  final SharedPreferences? _prefs;
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();

  StreamSubscription<AuthState>? _supabaseAuthSub;
  String? _cachedUserId;
  String? _cachedSessionToken;
  String? _cachedPhoneNumber;
  String? _cachedEmail;
  String? _cachedUserName;

  SupabaseAuthRepository({
    SupabaseClient? client,
    SharedPreferences? prefs,
  })  : _client = client ?? _getSafeSupabaseClient(),
        _prefs = prefs {
    _loadFromPrefsSync();
    _init();
  }

  void _loadFromPrefsSync() {
    if (_prefs != null) {
      final uid = _prefs.getString(_keyUserId);
      final token = _prefs.getString(_keySessionToken);
      if (isValidUuid(uid) && isValidJwt(token)) {
        _cachedUserId = uid;
        _cachedSessionToken = token;
        _cachedPhoneNumber = _prefs.getString(_keyPhoneNumber);
        _cachedEmail = _prefs.getString(_keyEmail);
        _cachedUserName = _prefs.getString(_keyUserName);
      } else if (uid != null || token != null) {
        _clearAuthDataSync();
      }
    }
  }

  void _clearAuthDataSync() {
    _cachedUserId = null;
    _cachedSessionToken = null;
    _cachedPhoneNumber = null;
    _cachedEmail = null;
    _cachedUserName = null;
    if (_prefs != null) {
      _prefs.remove(_keyUserId);
      _prefs.remove(_keySessionToken);
      _prefs.remove(_keyPhoneNumber);
      _prefs.remove(_keyEmail);
      _prefs.remove(_keyUserName);
    }
  }

  static SupabaseClient? _getSafeSupabaseClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Supabase is not initialized in offline mode or unit tests
      return null;
    }
  }

  Future<void> _init() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final uid = prefs.getString(_keyUserId);
      final token = prefs.getString(_keySessionToken);
      if (isValidUuid(uid) && isValidJwt(token)) {
        _cachedUserId ??= uid;
        _cachedSessionToken ??= token;
        _cachedPhoneNumber ??= prefs.getString(_keyPhoneNumber);
        _cachedEmail ??= prefs.getString(_keyEmail);
        _cachedUserName ??= prefs.getString(_keyUserName);
      } else if (uid != null || token != null) {
        await _clearAuthData();
      }
    } catch (e) {
      debugPrint('Failed to load cached auth from SharedPreferences: $e');
    }

    final client = _client;
    if (client != null) {
      final currentSession = client.auth.currentSession;
      if (currentSession != null &&
          isValidUuid(currentSession.user.id) &&
          isValidJwt(currentSession.accessToken)) {
        _cachedUserId = currentSession.user.id;
        _cachedSessionToken = currentSession.accessToken;
        _cachedPhoneNumber = currentSession.user.phone ?? _cachedPhoneNumber;
        _cachedEmail = currentSession.user.email ?? _cachedEmail;
        final meta = currentSession.user.userMetadata;
        if (meta != null && meta['full_name'] != null && (meta['full_name'] as String).isNotEmpty) {
          _cachedUserName = meta['full_name'] as String;
        }
        await _persistAuthData(_cachedUserId, _cachedSessionToken, _cachedPhoneNumber, _cachedEmail, _cachedUserName);
      }

      _supabaseAuthSub = client.auth.onAuthStateChange.listen((data) async {
        final session = data.session;
        if (session != null &&
            isValidUuid(session.user.id) &&
            isValidJwt(session.accessToken)) {
          _cachedUserId = session.user.id;
          _cachedSessionToken = session.accessToken;
          _cachedPhoneNumber = session.user.phone ?? _cachedPhoneNumber;
          _cachedEmail = session.user.email ?? _cachedEmail;
          final meta = session.user.userMetadata;
          if (meta != null && meta['full_name'] != null && (meta['full_name'] as String).isNotEmpty) {
            _cachedUserName = meta['full_name'] as String;
          }
          await _persistAuthData(_cachedUserId, _cachedSessionToken, _cachedPhoneNumber, _cachedEmail, _cachedUserName);
          if (!_authStateController.isClosed) {
            _authStateController.add(true);
          }
        } else if (data.event == AuthChangeEvent.signedOut) {
          _cachedUserId = null;
          _cachedSessionToken = null;
          _cachedPhoneNumber = null;
          _cachedEmail = null;
          _cachedUserName = null;
          await _clearAuthData();
          if (!_authStateController.isClosed) {
            _authStateController.add(false);
          }
        }
      });
    }

    if (!_authStateController.isClosed) {
      _authStateController.add(isAuthenticated);
    }
  }

  Future<void> _persistAuthData(
    String? userId,
    String? token,
    String? phone, [
    String? email,
    String? userName,
  ]) async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      if (userId != null) await prefs.setString(_keyUserId, userId);
      if (token != null) await prefs.setString(_keySessionToken, token);
      if (phone != null) await prefs.setString(_keyPhoneNumber, phone);
      if (email != null) await prefs.setString(_keyEmail, email);
      if (userName != null) await prefs.setString(_keyUserName, userName);
    } catch (e) {
      debugPrint('Error persisting Supabase auth: $e');
    }
  }

  Future<void> _clearAuthData() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.remove(_keyUserId);
      await prefs.remove(_keySessionToken);
      await prefs.remove(_keyPhoneNumber);
      await prefs.remove(_keyEmail);
      await prefs.remove(_keyUserName);
    } catch (e) {
      debugPrint('Error clearing Supabase auth: $e');
    }
  }

  @override
  bool get isAuthenticated {
    final client = _client;
    if (client != null && client.auth.currentSession != null) {
      final session = client.auth.currentSession!;
      if (isValidUuid(session.user.id) && isValidJwt(session.accessToken)) {
        return true;
      }
    }
    // Legitimate offline access for an already authenticated user
    if (_cachedUserId != null && _cachedSessionToken != null) {
      return isValidUuid(_cachedUserId) && isValidJwt(_cachedSessionToken);
    }
    return false;
  }

  @override
  String? get currentPhoneNumber {
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      return client.auth.currentUser!.phone ?? _cachedPhoneNumber;
    }
    return _cachedPhoneNumber;
  }

  @override
  String? get currentUserEmail {
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      return client.auth.currentUser!.email ?? _cachedEmail;
    }
    return _cachedEmail;
  }

  @override
  String? get currentUserName {
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      final meta = client.auth.currentUser!.userMetadata;
      if (meta != null && meta['full_name'] != null && (meta['full_name'] as String).isNotEmpty) {
        return meta['full_name'] as String;
      }
    }
    return _cachedUserName;
  }

  @override
  String? get currentUserId {
    final client = _client;
    if (client != null && client.auth.currentUser != null) {
      final id = client.auth.currentUser!.id;
      if (isValidUuid(id)) return id;
    }
    if (_cachedUserId != null && isValidUuid(_cachedUserId)) {
      return _cachedUserId;
    }
    return null;
  }

  @override
  String? get currentSessionToken {
    final client = _client;
    if (client != null && client.auth.currentSession != null) {
      final token = client.auth.currentSession!.accessToken;
      if (isValidJwt(token)) return token;
    }
    if (_cachedSessionToken != null && isValidJwt(_cachedSessionToken)) {
      return _cachedSessionToken;
    }
    return null;
  }

  @override
  Stream<bool> get authStateStream => _authStateController.stream;

  @override
  Future<void> sendOtp(String phoneNumber) async {
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10) {
      throw Exception('Please enter a valid 10-digit phone number');
    }

    final formattedPhone = phoneNumber.startsWith('+') ? phoneNumber : '+91$digitsOnly';
    final client = _client;

    if (client != null && SupabaseConfig.isConfigured) {
      await client.auth.signInWithOtp(phone: formattedPhone);
    } else {
      throw const AuthException(
        'Cloud authentication is unavailable. Please check your network connection.',
      );
    }
    _cachedPhoneNumber = formattedPhone;
  }

  @override
  Future<bool> verifyOtp(String phoneNumber, String otp) async {
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final formattedPhone = phoneNumber.startsWith('+') ? phoneNumber : '+91$digitsOnly';
    final trimmedOtp = otp.trim();
    final client = _client;

    if (client != null && SupabaseConfig.isConfigured) {
      try {
        final response = await client.auth.verifyOTP(
          phone: formattedPhone,
          token: trimmedOtp,
          type: OtpType.sms,
        );
        final session = response.session;
        if (session != null &&
            isValidUuid(session.user.id) &&
            isValidJwt(session.accessToken)) {
          _cachedUserId = session.user.id;
          _cachedSessionToken = session.accessToken;
          _cachedPhoneNumber = session.user.phone ?? formattedPhone;
          _cachedEmail = session.user.email;
          await _persistAuthData(_cachedUserId, _cachedSessionToken, _cachedPhoneNumber, _cachedEmail);
          _authStateController.add(true);
          return true;
        }
      } catch (e) {
        debugPrint('Supabase verifyOtp error: $e');
        rethrow;
      }
    }
    return false;
  }

  @override
  Future<SignUpResult> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedPassword = password.trim();
    final trimmedName = name.trim();
    final client = _client;

    if (client == null || !SupabaseConfig.isConfigured) {
      throw const AuthException(
        'Cloud authentication is unavailable. Please check your network connection.',
      );
    }

    try {
      final response = await client.auth.signUp(
        email: trimmedEmail,
        password: trimmedPassword,
        data: {
          'full_name': trimmedName,
        },
      );

      final user = response.user;
      if (user == null) {
        throw const AuthException('Failed to create user on Supabase Auth');
      }

      final session = response.session;
      if (session != null &&
          isValidUuid(session.user.id) &&
          isValidJwt(session.accessToken)) {
        // Genuine session immediately available
        _cachedUserId = session.user.id;
        _cachedSessionToken = session.accessToken;
        _cachedPhoneNumber = session.user.phone ?? _cachedPhoneNumber;
        _cachedEmail = session.user.email ?? trimmedEmail;
        _cachedUserName = trimmedName;

        await _persistAuthData(_cachedUserId, _cachedSessionToken, _cachedPhoneNumber, _cachedEmail, _cachedUserName);
        _authStateController.add(true);

        return SignUpResult(
          isSuccess: true,
          requiresEmailConfirmation: false,
          userId: session.user.id,
          email: trimmedEmail,
        );
      } else {
        // User created, but Supabase requires email verification before session is granted
        // Do not authenticate user, do not create fake token
        return SignUpResult(
          isSuccess: true,
          requiresEmailConfirmation: true,
          userId: user.id,
          email: trimmedEmail,
          message: 'Account created. Please check your email to confirm your account before signing in.',
        );
      }
    } catch (e) {
      debugPrint('Supabase signUpWithEmailAndPassword error: $e');
      rethrow;
    }
  }

  @override
  Future<bool> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedPassword = password.trim();
    final client = _client;

    if (client == null || !SupabaseConfig.isConfigured) {
      throw const AuthException(
        'Cloud authentication is unavailable. Please check your network connection.',
      );
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: trimmedEmail,
        password: trimmedPassword,
      );

      final session = response.session;
      if (session != null &&
          isValidUuid(session.user.id) &&
          isValidJwt(session.accessToken)) {
        _cachedUserId = session.user.id;
        _cachedSessionToken = session.accessToken;
        _cachedPhoneNumber = session.user.phone ?? _cachedPhoneNumber;
        _cachedEmail = session.user.email ?? trimmedEmail;
        final meta = session.user.userMetadata;
        if (meta != null && meta['full_name'] != null && (meta['full_name'] as String).isNotEmpty) {
          _cachedUserName = meta['full_name'] as String;
        }
        await _persistAuthData(_cachedUserId, _cachedSessionToken, _cachedPhoneNumber, _cachedEmail, _cachedUserName);
        _authStateController.add(true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Supabase signInWithEmailAndPassword error: $e');
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    final client = _client;
    if (client != null && SupabaseConfig.isConfigured) {
      try {
        await client.auth.signOut();
      } catch (e) {
        debugPrint('Remote signOut failed (clearing local session anyway): $e');
      }
    }
    _cachedUserId = null;
    _cachedSessionToken = null;
    _cachedPhoneNumber = null;
    _cachedEmail = null;
    _cachedUserName = null;
    await _clearAuthData();
    _authStateController.add(false);
  }

  void dispose() {
    _supabaseAuthSub?.cancel();
    _authStateController.close();
  }
}
