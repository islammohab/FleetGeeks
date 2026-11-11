import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Error from the Fleet Geeks API. [status] 0 means the network was not reachable (the command may be queued).
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.correlationId, this.code});

  final int status;
  final String message;
  final String? correlationId;

  /// Machine-readable conflict reason of a 409 (for example Stale, Superseded, AlreadyDecided, AmountChanged).
  final String? code;

  bool get isConflict => status == 409;

  bool get isNetwork => status == 0 || status == 502 || status == 503 || status == 504;

  /// Fleet Geeks / D365 refused the command: retrying the same command will not help.
  bool get isRejection => status >= 400 && status < 500 && status != 408 && status != 429;

  @override
  String toString() => message;
}

/// Thin JSON client: bearer token, Idempotency-Key for commands, ProblemDetails errors.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokenProvider, this.onUnauthorized, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final void Function()? onUnauthorized;
  final http.Client _http;

  Uri uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && '$v'.isNotEmpty) q[k] = '$v';
    });
    final u = Uri.parse('$baseUrl/api/v1$path');
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Future<dynamic> send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final request = http.Request(method, uri(path, query));
    request.headers['Accept'] = 'application/json';
    // wave 5: decisions record their channel (portal, link or app)
    request.headers['X-FG-Channel'] = 'App';
    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    if (idempotencyKey != null) request.headers['Idempotency-Key'] = idempotencyKey;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on TimeoutException {
      throw ApiException(0, 'The server did not answer in time.');
    } on Exception catch (e) {
      throw ApiException(0, 'Network unavailable ($e).');
    }
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) onUnauthorized?.call();
      var message = response.reasonPhrase ?? 'HTTP ${response.statusCode}';
      String? code;
      String? correlation = response.headers['x-correlation-id'];
      try {
        final problem = jsonDecode(text);
        if (problem is Map) {
          message = (problem['detail'] ?? problem['title'] ?? message).toString();
          code = problem['code']?.toString();
          correlation ??= problem['correlationId']?.toString();
        }
      } catch (_) {
        if (text.isNotEmpty) message = text;
      }
      throw ApiException(response.statusCode, message, correlationId: correlation, code: code);
    }
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query}) => send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, Map<String, Object?>? query, String? idempotencyKey}) =>
      send('POST', path, body: body ?? const <String, Object?>{}, query: query, idempotencyKey: idempotencyKey);

  /// Binary GET (evidence photos, PDF documents). Errors are thrown as [ApiException] like [send].
  Future<Uint8List> getBytes(String path, {Map<String, Object?>? query}) async {
    final request = http.Request('GET', uri(path, query));
    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 60)));
    } on TimeoutException {
      throw ApiException(0, 'The server did not answer in time.');
    } on Exception catch (e) {
      throw ApiException(0, 'Network unavailable ($e).');
    }
    if (response.statusCode >= 400) _decode(response);
    return response.bodyBytes;
  }

  /// Multipart upload (evidence photos and documents).
  Future<dynamic> upload(String path, {required String filePath, required String contentType, required Map<String, String> fields}) async {
    final parts = contentType.split('/');
    return _multipart(path, await http.MultipartFile.fromPath('file', filePath, contentType: MediaType(parts.first, parts.last)), fields);
  }

  /// Multipart upload of bytes held in memory (for example a signature drawn on the screen).
  Future<dynamic> uploadBytes(String path, {required List<int> bytes, required String fileName, required String contentType, required Map<String, String> fields}) {
    final parts = contentType.split('/');
    return _multipart(path, http.MultipartFile.fromBytes('file', bytes, filename: fileName, contentType: MediaType(parts.first, parts.last)), fields);
  }

  Future<dynamic> _multipart(String path, http.MultipartFile file, Map<String, String> fields) async {
    final request = http.MultipartRequest('POST', uri(path));
    final token = await tokenProvider();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    request.files.add(file);
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(minutes: 3)));
    } on Exception catch (e) {
      throw ApiException(0, 'Network unavailable ($e).');
    }
    return _decode(response);
  }
}
