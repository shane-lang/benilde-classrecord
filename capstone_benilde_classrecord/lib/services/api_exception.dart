class ApiException implements Exception {
  final String message;
  final int statusCode;

  final Map<String, List<String>>? fieldErrors;

  ApiException(this.message, this.statusCode, {this.fieldErrors});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;

  NetworkException([
    this.message =
        'Couldn’t reach the server. Check that the API is running and try again.',
  ]);

  @override
  String toString() => message;
}