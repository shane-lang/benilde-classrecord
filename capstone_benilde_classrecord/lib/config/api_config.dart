import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  static const int port = 5214;

  static const String lanHost = '192.168.1.10';

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:$port';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:

        return 'http://10.0.2.2:$port';
      case TargetPlatform.iOS:
        return 'http://localhost:$port';
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return 'http://localhost:$port';
      default:
        return 'http://$lanHost:$port';
    }
  }

  static Uri endpoint(String path) => Uri.parse('$baseUrl/api/$path');

  static const Duration timeout = Duration(seconds: 15);
}