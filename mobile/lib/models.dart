class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: (json['_id'] ?? json['id']).toString(),
        name: json['name'] as String? ?? 'Mon compte',
        email: json['email'] as String? ?? '',
      );

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }
}

class Greenhouse {
  Greenhouse({
    required this.id,
    required this.name,
    required this.online,
    required this.actuators,
    this.location,
  });

  final String id;
  final String name;
  final bool online;
  final String? location;
  final Map<String, Actuator> actuators;

  factory Greenhouse.fromJson(Map<String, dynamic> json) {
    final rawActuators =
        (json['actuators'] as Map?)?.cast<String, dynamic>() ?? {};
    return Greenhouse(
      id: (json['_id'] ?? json['id']).toString(),
      name: json['name'] as String? ?? 'Ma serre',
      online: json['online'] as bool? ?? false,
      location: json['location'] as String?,
      actuators: {
        for (final name in ['light', 'irrigation', 'ventilation'])
          name: Actuator.fromJson(
            (rawActuators[name] as Map?)?.cast<String, dynamic>() ?? {},
          ),
      },
    );
  }

  Greenhouse withActuator(String name, Actuator actuator) => Greenhouse(
        id: id,
        name: this.name,
        online: online,
        location: location,
        actuators: {...actuators, name: actuator},
      );
}

class Actuator {
  const Actuator({required this.state, required this.value});

  final bool state;
  final double value;

  factory Actuator.fromJson(Map<String, dynamic> json) => Actuator(
        state: json['state'] as bool? ?? false,
        value: (json['value'] as num?)?.toDouble() ?? 0,
      );
}

class SensorReading {
  const SensorReading({
    this.temperature,
    this.airHumidity,
    this.soilHumidity,
    this.lightLevel,
    this.measuredAt,
  });

  final double? temperature;
  final double? airHumidity;
  final double? soilHumidity;
  final double? lightLevel;
  final DateTime? measuredAt;

  factory SensorReading.fromJson(Map<String, dynamic> json) => SensorReading(
        temperature: (json['temperature'] as num?)?.toDouble(),
        airHumidity: (json['airHumidity'] as num?)?.toDouble(),
        soilHumidity: (json['soilHumidity'] as num?)?.toDouble(),
        lightLevel: (json['lightLevel'] as num?)?.toDouble(),
        measuredAt: DateTime.tryParse(json['measuredAt']?.toString() ?? ''),
      );
}

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.actuator,
    required this.enabled,
    required this.time,
    required this.days,
    required this.durationSeconds,
    required this.value,
  });

  final String id;
  final String name;
  final String actuator;
  final bool enabled;
  final String time;
  final List<int> days;
  final int durationSeconds;
  final double value;

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
        id: (json['_id'] ?? json['id']).toString(),
        name: json['name'] as String? ?? 'Routine',
        actuator: json['actuator'] as String? ?? 'irrigation',
        enabled: json['enabled'] as bool? ?? true,
        time: json['time'] as String? ?? '08:00',
        days: (json['days'] as List? ?? []).map((e) => e as int).toList(),
        durationSeconds: json['durationSeconds'] as int? ?? 60,
        value: (json['value'] as num?)?.toDouble() ?? 100,
      );
}
