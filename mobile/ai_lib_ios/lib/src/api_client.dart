import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, this.token, this.onUnauthorized})
    : baseUrl = _normalize(baseUrl);

  final String baseUrl;
  String? token;
  final void Function()? onUnauthorized;

  static String _normalize(String value) {
    var result = value.trim();
    if (result.isEmpty) result = 'http://127.0.0.1:8765';
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('/api/v1')) {
      result = result.substring(0, result.length - 7);
    }
    return result;
  }

  Uri uri(String path, [Map<String, Object?> query = const {}]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final resolved = Uri.parse('$baseUrl$normalized');
    return query.isEmpty
        ? resolved
        : resolved.replace(
            queryParameters: query.map((key, value) => MapEntry(key, '$value')),
          );
  }

  Uri mediaUri(String path) => uri(path);

  Map<String, String> get headers => {
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  Future<dynamic> get(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    final response = await http.get(uri(path, query), headers: headers);
    return _decode(response);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
  }) async {
    final requestHeaders = {...headers, 'Content-Type': 'application/json'};
    final response = await http.post(
      uri(path, query),
      headers: requestHeaders,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> patch(String path, Object body) async {
    final response = await http.patch(
      uri(path),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> delete(String path) async {
    final response = await http.delete(uri(path), headers: headers);
    return _decode(response);
  }

  Future<Uint8List> download(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    final response = await http.get(uri(path, query), headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) onUnauthorized?.call();
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  Future<JsonMap> upload(
    List<({String name, Uint8List bytes, String filename, String contentType})>
    files,
    Map<String, String> fields,
  ) async {
    final request = http.MultipartRequest('POST', uri('/api/v1/assets/upload'));
    request.headers.addAll(headers);
    request.fields.addAll(fields);
    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          file.name,
          file.bytes,
          filename: file.filename,
          contentType: _mediaType(file.contentType),
        ),
      );
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final result = _decode(response);
    return Map<String, dynamic>.from(result as Map);
  }

  http.MediaType _mediaType(String value) {
    final parts = value.split('/');
    if (parts.length == 2) return http.MediaType(parts[0], parts[1]);
    return http.MediaType('image', 'jpeg');
  }

  dynamic _decode(http.Response response) {
    dynamic data;
    try {
      data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) onUnauthorized?.call();
      throw ApiException(
        _errorMessage(response, decoded: data),
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  String _errorMessage(http.Response response, {dynamic decoded}) {
    final body =
        decoded ??
        (() {
          try {
            return jsonDecode(utf8.decode(response.bodyBytes));
          } catch (_) {
            return null;
          }
        })();
    if (body is Map && body['detail'] != null) return body['detail'].toString();
    if (response.statusCode == 401) return '登录已过期，请重新登录';
    return '服务器请求失败（${response.statusCode}）';
  }
}
