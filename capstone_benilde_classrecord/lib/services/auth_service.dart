import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_user.dart';
import 'api_client.dart';
import 'api_exception.dart';

class AuthService extends ChangeNotifier {
  AuthService({ApiClient? client}) : _api = client ?? ApiClient();

  static final AuthService instance = AuthService();

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _expiryKey = 'auth_expires_at';

  final ApiClient _api;

  AuthUser? _user;
  String? _token;
  DateTime? _expiresAt;

  AuthUser? get currentUser => _user;
  String? get token => _token;
  bool get isSignedIn => _token != null && _user != null && !_isExpired;

  bool get _isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  ApiClient get api => _api;

  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final userJson = prefs.getString(_userKey);
      final expiry = prefs.getString(_expiryKey);
      if (token == null || userJson == null) return false;

      _token = token;
      _api.authToken = token;
      _user = AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      _expiresAt = expiry == null ? null : DateTime.tryParse(expiry);

      if (_isExpired) {
        await signOut();
        return false;
      }

      try {
        final me = await _api.get('auth/me');
        _user = AuthUser.fromJson(me);
        notifyListeners();
        return true;
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          await signOut();
          return false;
        }

        return true;
      } on NetworkException {

        return true;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.post('auth/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });

    await _clearMustChangePassword();
  }

  Future<void> _clearMustChangePassword() async {
    final current = _user;
    if (current == null || !current.mustChangePassword) return;
    _user = current.copyWith(mustChangePassword: false);

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_userKey) != null) {
        await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
      }
    } catch (_) {

    }

    notifyListeners();
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final body = await _api.post('auth/login', {
      'email': email.trim(),
      'password': password,
    });

    final token = body['token'] as String?;
    final teacher = body['teacher'];
    if (token == null || teacher is! Map<String, dynamic>) {
      throw ApiException('The server sent an unexpected reply.', 500);
    }

    _token = token;
    _api.authToken = token;
    _user = AuthUser.fromJson(teacher);
    _expiresAt = DateTime.tryParse(body['expiresAt'] as String? ?? '');

    if (rememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
      if (_expiresAt != null) {
        await prefs.setString(_expiryKey, _expiresAt!.toIso8601String());
      }
    }

    notifyListeners();
    return _user!;
  }

  Future<AuthUser> register({
    required String email,
    required String password,
    required String fullName,
    String? department,
  }) async {
    final body = await _api.post('auth/register', {
      'email': email.trim(),
      'password': password,
      'fullName': fullName.trim(),
      'department': department?.trim(),
    });

    _token = body['token'] as String?;
    _api.authToken = _token;
    _user = AuthUser.fromJson(body['teacher'] as Map<String, dynamic>);
    _expiresAt = DateTime.tryParse(body['expiresAt'] as String? ?? '');
    notifyListeners();
    return _user!;
  }

  Future<AuthUser> acceptInvite({
    required String email,
    required String code,
    required String password,
    bool rememberMe = false,
  }) async {
    final body = await _api.post('auth/accept-invite', {
      'email': email.trim(),
      'code': code.trim(),
      'password': password,
    });

    final token = body['token'] as String?;
    final teacher = body['teacher'];
    if (token == null || teacher is! Map<String, dynamic>) {
      throw ApiException('The server sent an unexpected reply.', 500);
    }

    _token = token;
    _api.authToken = token;
    _user = AuthUser.fromJson(teacher);
    _expiresAt = DateTime.tryParse(body['expiresAt'] as String? ?? '');

    if (rememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
      if (_expiresAt != null) {
        await prefs.setString(_expiryKey, _expiresAt!.toIso8601String());
      }
    }

    notifyListeners();
    return _user!;
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    _expiresAt = null;
    _api.authToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_expiryKey);

    notifyListeners();
  }
}