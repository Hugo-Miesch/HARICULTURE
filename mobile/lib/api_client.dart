import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'serial_number_input.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    this.requestTimeout = const Duration(seconds: 10),
  }) : baseUrl = _normalizeBaseUrl(baseUrl);

  final String baseUrl;
  final Duration requestTimeout;
  String? token;

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    return normalized.endsWith('/api') ? normalized : '$normalized/api';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get mediaHeaders => {
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri resolveMediaUrl(String value) {
    final uri = Uri.parse(value);
    if (uri.hasScheme) return uri;
    return Uri.parse('$baseUrl/').resolve(value);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response response;
    final encoded = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'POST':
          response = await http
              .post(uri, headers: _headers, body: encoded)
              .timeout(requestTimeout);
          break;
        case 'PATCH':
          response = await http
              .patch(uri, headers: _headers, body: encoded)
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          response =
              await http.delete(uri, headers: _headers).timeout(requestTimeout);
          break;
        default:
          response =
              await http.get(uri, headers: _headers).timeout(requestTimeout);
      }
    } on TimeoutException {
      throw ApiException(
        'API injoignable après ${requestTimeout.inSeconds} secondes.',
      );
    } on http.ClientException catch (exception) {
      throw ApiException('Connexion à l’API impossible : ${exception.message}');
    }

    if (response.statusCode == 204) return {};
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final nestedError = decoded['error'];
      final nestedMessage =
          nestedError is Map ? nestedError['message']?.toString() : null;
      throw ApiException(
        decoded['message']?.toString() ??
            nestedMessage ??
            'Une erreur est survenue',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<String> login(String email, String password) async {
    final data = await _request(
      'POST',
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return data['token'] as String;
  }

  Future<String> register(String name, String email, String password) async {
    final data = await _request(
      'POST',
      '/auth/register',
      body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
    return data['token'] as String;
  }

  Future<UserProfile> currentUser() async {
    final data = await _request('GET', '/auth/me');
    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<Greenhouse>> getGreenhouses() async {
    final data = await _request('GET', '/greenhouses');
    return (data['greenhouses'] as List)
        .map((e) => Greenhouse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<GalleryPhoto>> gallery({int limit = 100}) async {
    final data = await _request('GET', '/gallery?limit=$limit');
    return (data['photos'] as List? ?? const [])
        .map(
          (photo) =>
              GalleryPhoto.fromJson((photo as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  http.Request cameraStreamRequest(String greenhouseId) => http.Request(
        'GET',
        Uri.parse('$baseUrl/greenhouses/$greenhouseId/camera/stream'),
      )..headers.addAll(_headers);

  Future<Greenhouse> getGreenhouse(String greenhouseId) async {
    final data = await _request('GET', '/greenhouses/$greenhouseId');
    return Greenhouse.fromJson(data['greenhouse'] as Map<String, dynamic>);
  }

  Future<Greenhouse> pairGreenhouse(String code, {String? name}) async {
    final data = await _request(
      'POST',
      '/greenhouses/pair',
      body: {
        'code': normalizeSerialNumber(code),
        if (name?.trim().isNotEmpty == true) 'name': name,
      },
    );
    return Greenhouse.fromJson(data['greenhouse'] as Map<String, dynamic>);
  }

  Future<Actuator> setActuator(
    String greenhouseId,
    String actuator,
    bool state, {
    double value = 100,
  }) async {
    final data = await _request(
      'PATCH',
      '/greenhouses/$greenhouseId/actuators/$actuator',
      body: {'state': state, 'value': value},
    );
    return Actuator.fromJson(data['actuator'] as Map<String, dynamic>);
  }

  Future<SensorReading?> latestReading(String greenhouseId) async {
    final data = await _request(
      'GET',
      '/greenhouses/$greenhouseId/sensors/latest',
    );
    final reading = data['reading'];
    return reading == null
        ? null
        : SensorReading.fromJson(reading as Map<String, dynamic>);
  }

  Future<SensorReading> collectReading(String greenhouseId) async {
    final data = await _request(
      'POST',
      '/greenhouses/$greenhouseId/sensors/collect',
    );
    return SensorReading.fromJson(data['reading'] as Map<String, dynamic>);
  }

  Future<List<SensorReading>> readings(String greenhouseId) async {
    final data = await _request(
      'GET',
      '/greenhouses/$greenhouseId/sensors?limit=30',
    );
    return (data['readings'] as List)
        .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Routine>> routines(String greenhouseId) async {
    final data = await _request(
      'GET',
      '/greenhouses/$greenhouseId/routines',
    );
    return (data['routines'] as List)
        .map((e) => Routine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Routine> createRoutine(
    String greenhouseId,
    Map<String, dynamic> values,
  ) async {
    final data = await _request(
      'POST',
      '/greenhouses/$greenhouseId/routines',
      body: values,
    );
    return Routine.fromJson(data['routine'] as Map<String, dynamic>);
  }

  Future<Routine> toggleRoutine(
    String greenhouseId,
    Routine routine,
    bool enabled,
  ) async {
    final data = await _request(
      'PATCH',
      '/greenhouses/$greenhouseId/routines/${routine.id}',
      body: {'enabled': enabled},
    );
    return Routine.fromJson(data['routine'] as Map<String, dynamic>);
  }

  Future<void> deleteRoutine(String greenhouseId, String routineId) => _request(
        'DELETE',
        '/greenhouses/$greenhouseId/routines/$routineId',
      );
}
