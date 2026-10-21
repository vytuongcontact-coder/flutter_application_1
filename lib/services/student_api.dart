import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/menu_nav.dart';
import '../models/student_profile.dart';
import 'token_store.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class _Tokens {
  const _Tokens(this.access, this.refresh);
  final String access, refresh;
  factory _Tokens.parse(Map<String, dynamic> json) {
    final access = json['token'];
    final refresh = json['refresh_token'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const ApiException(
        'Phản hồi đăng nhập không hợp lệ. Vui lòng đăng nhập lại.',
      );
    }
    return _Tokens(access, refresh);
  }
  String encode() => jsonEncode({'token': access, 'refresh_token': refresh});
}

class StudentApi {
  StudentApi({http.Client? client, TokenStore? store, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _store = store ?? SecureTokenStore(),
      _baseUrl =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'UEH_API_URL',
              defaultValue: 'https://api.ngoisaoviet.info',
            ),
          ) {
    if (_baseUrl.scheme != 'https' || !_baseUrl.hasAuthority) {
      throw ArgumentError('UEH_API_URL phải là HTTPS.');
    }
  }

  final http.Client _client;
  final TokenStore _store;
  final Uri _baseUrl;
  _Tokens? _tokens;
  Future<void>? _refreshing;
  Future<void> _storageQueue = Future.value();
  int _generation = 0;
  void Function()? onSessionExpired;
  bool get hasSession => _tokens != null;

  // Serialize writes/deletes so a late refresh cannot restore a logged-out session.
  Future<void> _persist(Future<void> Function() operation) {
    final result = _storageQueue.then((_) => operation());
    _storageQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> restore() async {
    final generation = _generation;
    final value = await _store.read();
    if (value == null || generation != _generation) return;
    try {
      _tokens = _Tokens.parse(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      await logout();
    }
  }

  Future<void> login(String studentId, String password) async {
    final generation = ++_generation;
    final response = await _send(
      'POST',
      '/api/login',
      body: {'mssv': studentId.trim(), 'mat_khau': password},
    );
    final tokens = _Tokens.parse(_decode(response));
    if (generation != _generation) return;
    await _persist(() => _store.write(tokens.encode()));
    if (generation == _generation) _tokens = tokens;
  }

  Future<void> logout() async {
    ++_generation;
    _tokens = null;
    await _persist(_store.clear);
  }

  Future<void> _expire(int generation) async {
    if (generation != _generation) return;
    final clear = logout();
    onSessionExpired?.call();
    await clear;
  }

  Future<void> _refresh(int generation) async {
    final tokens = _tokens;
    if (tokens == null) {
      throw const ApiException('Vui lòng đăng nhập lại.', statusCode: 401);
    }
    try {
      // Never replay a one-use refresh token, including after an ambiguous timeout.
      // Remove the old persisted pair before consuming it so an app crash cannot
      // replay an already-rotated token on the next launch.
      await _persist(_store.clear);
      if (generation != _generation) {
        throw const ApiException('Phiên đăng nhập đã thay đổi.', statusCode: 401);
      }
      final response = await _send(
        'POST',
        '/api/refresh-token',
        body: {'refresh_token': tokens.refresh},
      );
      final replacement = _Tokens.parse(_decode(response));
      if (generation != _generation) {
        throw const ApiException(
          'Phiên đăng nhập đã thay đổi.',
          statusCode: 401,
        );
      }
      await _persist(() => _store.write(replacement.encode()));
      if (generation == _generation) _tokens = replacement;
    } catch (_) {
      await _expire(generation);
      throw const ApiException(
        'Phiên đăng nhập đã hết hạn hoặc bị gián đoạn. Vui lòng đăng nhập lại.',
        statusCode: 401,
      );
    }
  }

  Future<Map<String, dynamic>> _authorized(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async => _decode(await _authorizedResponse(method, path, body: body));

  // Gửi request có Bearer token; gặp 401 thì refresh một lần rồi gửi lại một lần.
  // Trả response thô để mỗi endpoint tự decode object hay array.
  Future<http.Response> _authorizedResponse(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final generation = _generation;
    final token = _tokens?.access;
    if (token == null) {
      throw const ApiException(
        'Vui lòng đăng nhập để tiếp tục.',
        statusCode: 401,
      );
    }
    var response = await _send(method, path, body: body, token: token);
    if (generation != _generation) {
      throw const ApiException('Phiên đăng nhập đã thay đổi.', statusCode: 401);
    }
    if (response.statusCode == 401) {
      if (_tokens?.access == token) {
        final pending = _refreshing ??= _refresh(generation);
        try {
          await pending;
        } finally {
          if (identical(_refreshing, pending)) _refreshing = null;
        }
      }
      if (generation != _generation || _tokens == null) {
        throw const ApiException('Vui lòng đăng nhập lại.', statusCode: 401);
      }
      response = await _send(method, path, body: body, token: _tokens!.access);
      if (generation != _generation) {
        throw const ApiException(
          'Phiên đăng nhập đã thay đổi.',
          statusCode: 401,
        );
      }
      if (response.statusCode == 401) {
        await _expire(generation);
        throw const ApiException(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          statusCode: 401,
        );
      }
    }
    return response;
  }

  Future<StudentProfile> studentInfo() async {
    final json = await _authorized('GET', '/api/student-info');
    try {
      return StudentProfile.fromJson(json);
    } on FormatException {
      throw const ApiException(
        'Thông tin sinh viên trả về chưa đầy đủ. Vui lòng thử lại.',
      );
    }
  }

  /// GET /api/menu: server trả về MẢNG JSON, đã sắp theo `ordering`.
  Future<List<MenuNav>> menu() async {
    final json = _decodeList(await _authorizedResponse('GET', '/api/menu'));
    try {
      final menus = [for (final item in json) MenuNav.fromJson(item)];
      if (menus.map((menu) => menu.id).toSet().length != menus.length) {
        throw const FormatException('Trùng id menu.');
      }
      return menus;
    } on FormatException {
      throw const ApiException(
        'Dữ liệu menu trả về không hợp lệ. Vui lòng thử lại.',
      );
    }
  }

  Future<Map<String, dynamic>> attend(
    String code, {
    double? latitude,
    double? longitude,
  }) => _authorized(
    'POST',
    '/api/attendance',
    body: {
      'code': code.trim().toUpperCase(),
      if (latitude != null && longitude != null) ...{
        'latitude': latitude,
        'longitude': longitude,
      },
    },
  );

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final request = http.Request(method, _baseUrl.resolve(path))
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });
      if (body != null) request.body = jsonEncode(body);
      return await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const ApiException(
        'Kết nối quá thời gian chờ. Vui lòng kiểm tra mạng và thử lại.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.',
      );
    }
  }

  // Login, refresh, student-info, attendance: body phải là JSON object.
  Map<String, dynamic> _decode(http.Response response) {
    final value = _decodeJson(response);
    if (value is Map<String, dynamic> && value.isNotEmpty) return value;
    throw const ApiException('Máy chủ trả về dữ liệu không hợp lệ.');
  }

  // Menu: body phải là JSON array (được phép rỗng).
  List<dynamic> _decodeList(http.Response response) {
    final value = _decodeJson(response);
    if (value is List<dynamic>) return value;
    throw const ApiException('Máy chủ trả về dữ liệu không hợp lệ.');
  }

  // Response 2xx: trả JSON đã parse (object, array hoặc null nếu không phải JSON).
  // Response lỗi: ném ApiException với message của server.
  Object? _decodeJson(http.Response response) {
    Object? value;
    try {
      value = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      /* Handle empty 401 and non-JSON gateway responses below. */
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return value;
    final data = value is Map<String, dynamic> ? value : const <String, dynamic>{};
    final message = data['message'];
    final errors = data['errors'];
    throw ApiException(
      message is String && message.isNotEmpty
          ? message
          : errors is Map
          ? 'Dữ liệu chưa hợp lệ. Vui lòng kiểm tra các trường đã nhập.'
          : response.statusCode == 401
          ? 'MSSV hoặc mật khẩu không đúng.'
          : 'Máy chủ chưa xử lý được yêu cầu (${response.statusCode}). Vui lòng thử lại.',
      statusCode: response.statusCode,
    );
  }

  void close() {
    ++_generation;
    _client.close();
  }
}
