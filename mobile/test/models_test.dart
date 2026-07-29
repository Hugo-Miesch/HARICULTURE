import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hariculture/api_client.dart';
import 'package:hariculture/models.dart';
import 'package:hariculture/serial_number_input.dart';

void main() {
  test('convertit une serre et ses actionneurs depuis l API', () {
    final greenhouse = Greenhouse.fromJson({
      '_id': 'serre-1',
      'name': 'Serre principale',
      'online': true,
      'actuators': {
        'light': {'state': true, 'value': 80},
      },
    });

    expect(greenhouse.id, 'serre-1');
    expect(greenhouse.online, isTrue);
    expect(greenhouse.actuators['light']?.state, isTrue);
    expect(greenhouse.actuators['irrigation']?.state, isFalse);
  });

  test('convertit un relevé de capteurs', () {
    final reading = SensorReading.fromJson({
      'temperature': 23.4,
      'airHumidity': 63,
      'soilHumidity': 48,
      'lightLevel': 750,
      'measuredAt': '2026-07-28T10:00:00.000Z',
    });

    expect(reading.temperature, 23.4);
    expect(reading.airHumidity, 63);
    expect(reading.measuredAt, isNotNull);
  });

  test('convertit le profil retourné par auth me', () {
    final profile = UserProfile.fromJson({
      '_id': 'user-1',
      'name': 'Alice Martin',
      'email': 'alice@example.com',
    });

    expect(profile.name, 'Alice Martin');
    expect(profile.email, 'alice@example.com');
    expect(profile.initials, 'AM');
  });

  test('affiche le message d’erreur imbriqué de l API', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestFuture = server.first;
    final api = ApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}/api',
    );
    final responseFuture = api.getGreenhouses();

    final request = await requestFuture;
    request.response
      ..statusCode = HttpStatus.unauthorized
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'error': {'message': 'Authentification requise'},
        }),
      );
    await request.response.close();

    await expectLater(
      responseFuture,
      throwsA(
        isA<ApiException>()
            .having(
              (exception) => exception.message,
              'message',
              'Authentification requise',
            )
            .having(
              (exception) => exception.statusCode,
              'statusCode',
              HttpStatus.unauthorized,
            ),
      ),
    );
    await server.close(force: true);
  });

  test('normalise un SN de 4 caractères', () {
    expect(normalizeSerialNumber(' ab12 '), 'AB12');
  });

  test('construit le flux caméra authentifié depuis la racine API', () {
    final api = ApiClient(baseUrl: 'http://10.123.226.164:3000/');
    api.token = 'jwt-test';

    final request = api.cameraStreamRequest('serre-1');

    expect(
      request.url.toString(),
      'http://10.123.226.164:3000/api/greenhouses/serre-1/camera/stream',
    );
    expect(request.headers['Authorization'], 'Bearer jwt-test');
  });

  test('convertit une photo de galerie et résout son URL protégée', () {
    final photo = GalleryPhoto.fromJson({
      'id': 'photo-1',
      'greenhouseId': 'serre-1',
      'greenhouseName': 'Serre de test',
      'imageUrl': '/api/gallery/photo-1/file',
      'capturedAt': '2026-07-29T15:30:00.000Z',
    });
    final api = ApiClient(baseUrl: 'http://10.123.226.164:3000/');
    api.token = 'jwt-test';

    expect(photo.greenhouseName, 'Serre de test');
    expect(photo.thumbnailUrl, photo.imageUrl);
    expect(
      api.resolveMediaUrl(photo.imageUrl).toString(),
      'http://10.123.226.164:3000/api/gallery/photo-1/file',
    );
    expect(api.mediaHeaders['Authorization'], 'Bearer jwt-test');
  });
}
