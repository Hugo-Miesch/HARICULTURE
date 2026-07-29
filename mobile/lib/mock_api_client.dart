import 'api_client.dart';
import 'models.dart';
import 'serial_number_input.dart';

class MockApiClient extends ApiClient {
  MockApiClient() : super(baseUrl: 'mock://hariculture');

  final Duration _latency = const Duration(milliseconds: 350);

  late Greenhouse _greenhouse = Greenhouse(
    id: 'demo-greenhouse',
    name: 'Serre des tomates',
    online: true,
    location: 'Jardin nord',
    actuators: const {
      'light': Actuator(state: true, value: 72),
      'irrigation': Actuator(state: false, value: 0),
      'ventilation': Actuator(state: true, value: 40),
    },
  );

  final Greenhouse _secondaryGreenhouse = Greenhouse(
    id: 'tropical-greenhouse',
    name: 'Jardin tropical',
    online: true,
    location: 'Véranda',
    actuators: const {
      'light': Actuator(state: false, value: 0),
      'irrigation': Actuator(state: true, value: 60),
      'ventilation': Actuator(state: false, value: 0),
    },
  );

  final List<Routine> _routines = [
    const Routine(
      id: 'routine-morning-water',
      name: 'Arrosage du matin',
      actuator: 'irrigation',
      enabled: true,
      time: '07:30',
      days: [1, 2, 3, 4, 5, 6],
      durationSeconds: 120,
      value: 100,
    ),
    const Routine(
      id: 'routine-light',
      name: 'Lumière de croissance',
      actuator: 'light',
      enabled: true,
      time: '06:45',
      days: [0, 1, 2, 3, 4, 5, 6],
      durationSeconds: 43200,
      value: 75,
    ),
    const Routine(
      id: 'routine-ventilation',
      name: 'Aération de midi',
      actuator: 'ventilation',
      enabled: false,
      time: '12:30',
      days: [1, 2, 3, 4, 5],
      durationSeconds: 900,
      value: 50,
    ),
  ];

  List<SensorReading> _readings(String greenhouseId) {
    final now = DateTime.now();
    final tropical = greenhouseId == _secondaryGreenhouse.id;
    return List.generate(30, (index) {
      final cycle = index % 8;
      return SensorReading(
        temperature: (tropical ? 26.1 : 23.6) - (index * 0.07) + (cycle * 0.12),
        airHumidity: (tropical ? 72 : 61) + ((index % 5) * 0.8),
        soilHumidity:
            (tropical ? 64 : 47) - (index * 0.11) + ((index % 4) * 0.5),
        lightLevel: (tropical ? 620 : 780) - (index * 8) + ((index % 6) * 18),
        measuredAt: now.subtract(Duration(minutes: index * 30)),
      );
    });
  }

  Future<void> _wait() => Future<void>.delayed(_latency);

  @override
  Future<String> login(String email, String password) async {
    await _wait();
    if (email.trim().isEmpty || password.length < 8) {
      throw ApiException(
        'Utilisez un email et un mot de passe de 8 caractères.',
      );
    }
    return 'demo-session';
  }

  @override
  Future<String> register(String name, String email, String password) =>
      login(email, password);

  @override
  Future<UserProfile> currentUser() async {
    await _wait();
    return const UserProfile(
      id: 'demo-user',
      name: 'Camille Jardin',
      email: 'demo@hariculture.fr',
    );
  }

  @override
  Future<List<Greenhouse>> getGreenhouses() async {
    await _wait();
    return [_greenhouse, _secondaryGreenhouse];
  }

  @override
  Future<Greenhouse> getGreenhouse(String greenhouseId) async {
    await _wait();
    if (greenhouseId == _greenhouse.id) return _greenhouse;
    if (greenhouseId == _secondaryGreenhouse.id) return _secondaryGreenhouse;
    if (greenhouseId == 'paired-greenhouse-0000') {
      return _pairedGreenhouse();
    }
    throw ApiException('Serre introuvable ou accès refusé', statusCode: 404);
  }

  @override
  Future<Greenhouse> pairGreenhouse(String code, {String? name}) async {
    await _wait();
    final normalizedCode = normalizeSerialNumber(code);
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(normalizedCode)) {
      throw ApiException('Le code doit contenir 4 caractères.');
    }
    if (normalizedCode != '0000') {
      throw ApiException('Création impossible : SN inexistant.');
    }
    return _pairedGreenhouse(name: name);
  }

  Greenhouse _pairedGreenhouse({String? name}) {
    return Greenhouse(
      id: 'paired-greenhouse-0000',
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'Serre 0000',
      online: true,
      location: 'Nouvelle installation',
      actuators: const {
        'light': Actuator(state: false, value: 0),
        'irrigation': Actuator(state: false, value: 0),
        'ventilation': Actuator(state: false, value: 0),
      },
    );
  }

  @override
  Future<Actuator> setActuator(
    String greenhouseId,
    String actuator,
    bool state, {
    double value = 100,
  }) async {
    await _wait();
    final result = Actuator(state: state, value: state ? value : 0);
    if (greenhouseId == _greenhouse.id) {
      _greenhouse = _greenhouse.withActuator(actuator, result);
    }
    return result;
  }

  @override
  Future<SensorReading?> latestReading(String greenhouseId) async {
    await _wait();
    return _readings(greenhouseId).first;
  }

  @override
  Future<SensorReading> collectReading(String greenhouseId) async {
    await _wait();
    return _readings(greenhouseId).first;
  }

  @override
  Future<List<SensorReading>> readings(String greenhouseId) async {
    await _wait();
    return _readings(greenhouseId);
  }

  @override
  Future<List<Routine>> routines(String greenhouseId) async {
    await _wait();
    return List.unmodifiable(_routines);
  }

  @override
  Future<Routine> createRoutine(
    String greenhouseId,
    Map<String, dynamic> values,
  ) async {
    await _wait();
    final routine = Routine(
      id: 'routine-${DateTime.now().microsecondsSinceEpoch}',
      name: values['name'] as String,
      actuator: values['actuator'] as String,
      enabled: values['enabled'] as bool? ?? true,
      time: values['time'] as String,
      days: (values['days'] as List).cast<int>(),
      durationSeconds: values['durationSeconds'] as int,
      value: (values['value'] as num?)?.toDouble() ?? 100,
    );
    _routines.add(routine);
    return routine;
  }

  @override
  Future<Routine> toggleRoutine(
    String greenhouseId,
    Routine routine,
    bool enabled,
  ) async {
    await _wait();
    final updated = Routine(
      id: routine.id,
      name: routine.name,
      actuator: routine.actuator,
      enabled: enabled,
      time: routine.time,
      days: routine.days,
      durationSeconds: routine.durationSeconds,
      value: routine.value,
    );
    final index = _routines.indexWhere((item) => item.id == routine.id);
    if (index >= 0) _routines[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteRoutine(String greenhouseId, String routineId) async {
    await _wait();
    _routines.removeWhere((routine) => routine.id == routineId);
  }
}
