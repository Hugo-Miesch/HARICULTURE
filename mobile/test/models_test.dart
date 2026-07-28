import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hariculture/api_client.dart';
import 'package:hariculture/mock_api_client.dart';
import 'package:hariculture/models.dart';

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

  test('la démo fonctionne sans API', () async {
    final api = MockApiClient();
    final greenhouses = await api.getGreenhouses();
    final greenhouse = greenhouses.first;

    expect(greenhouses, hasLength(2));
    expect(greenhouse.online, isTrue);
    expect(await api.latestReading(greenhouse.id), isNotNull);
    expect(await api.routines(greenhouse.id), hasLength(3));

    final irrigation = await api.setActuator(
      greenhouse.id,
      'irrigation',
      true,
    );
    expect(irrigation.state, isTrue);
  });

  test('le SN accepte 4 caractères mais seul 0000 existe en démo', () async {
    final api = MockApiClient();

    await expectLater(
      api.pairGreenhouse('ab12'),
      throwsA(
        isA<ApiException>().having(
          (exception) => exception.message,
          'message',
          'Création impossible : SN inexistant.',
        ),
      ),
    );

    final greenhouse = await api.pairGreenhouse('0000');
    expect(greenhouse.id, 'paired-greenhouse-0000');
    expect(greenhouse.name, 'Serre 0000');
  });
}
