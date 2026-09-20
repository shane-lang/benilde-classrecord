import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String? authToken;

  static void Function()? onSessionExpired;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Future<Map<String, dynamic>> get(String path) async =>
      _asMap(await _send(() => _client.get(ApiConfig.endpoint(path), headers: _headers)));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async =>
      _asMap(await _send(() => _client.post(
            ApiConfig.endpoint(path),
            headers: _headers,
            body: jsonEncode(body),
          )));

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async =>
      _asMap(await _send(() => _client.put(
            ApiConfig.endpoint(path),
            headers: _headers,
            body: jsonEncode(body),
          )));

  Future<void> delete(String path) async =>
      _send(() => _client.delete(ApiConfig.endpoint(path), headers: _headers));

  Future<List<Map<String, dynamic>>> getList(String path) async =>
      _asList(await _send(() => _client.get(ApiConfig.endpoint(path), headers: _headers)));

  Future<List<Map<String, dynamic>>> postList(String path, Map<String, dynamic> body) async =>
      _asList(await _send(() => _client.post(
            ApiConfig.endpoint(path),
            headers: _headers,
            body: jsonEncode(body),
          )));

  Future<List<Map<String, dynamic>>> putList(String path, Map<String, dynamic> body) async =>
      _asList(await _send(() => _client.put(
            ApiConfig.endpoint(path),
            headers: _headers,
            body: jsonEncode(body),
          )));

  Map<String, dynamic> _asMap(Object? decoded) =>
      decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

  List<Map<String, dynamic>> _asList(Object? decoded) {
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  Future<Object?> _send(Future<http.Response> Function() request) async {
    late http.Response response;
    try {
      response = await request().timeout(ApiConfig.timeout);
    } catch (_) {

      throw NetworkException();
    }

    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {

      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    if (response.statusCode == 401 && authToken != null) {
      onSessionExpired?.call();
    }

    final body = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};

    throw ApiException(
      body['message'] as String? ?? _messageForStatus(response.statusCode),
      response.statusCode,
      fieldErrors: _parseFieldErrors(body['errors']),
    );
  }

  Map<String, List<String>>? _parseFieldErrors(Object? raw) {
    if (raw is! Map) return null;
    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      if (value is List) result['$key'] = value.map((e) => '$e').toList();
    });
    return result.isEmpty ? null : result;
  }

  String _messageForStatus(int code) => switch (code) {
        400 => 'Please check the form and try again.',
        401 => 'Your session has expired. Log in again.',
        403 => 'This account isn’t allowed to do that.',
        404 => 'That wasn’t found on the server.',
        409 => 'That conflicts with something already saved.',
        429 => 'Too many attempts. Wait a minute and try again.',
        >= 500 => 'The server ran into a problem. Try again in a moment.',
        _ => 'Something went wrong. Try again.',
      };

  void close() => _client.close();
}