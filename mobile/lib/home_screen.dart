import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'models.dart';

String _formatIrrigationDelay(int seconds, {bool compact = false}) {
  if (seconds < 60) {
    return compact ? '$seconds s' : '$seconds secondes';
  }
  final minutes = seconds ~/ 60;
  if (compact) return '$minutes min';
  return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
}

const _plantChoices = [
  _PlantChoice('🍅', 'Tomate'),
  _PlantChoice('🌱', 'Pousse'),
  _PlantChoice('🌿', 'Feuille'),
  _PlantChoice('🌵', 'Cactus'),
  _PlantChoice('🌻', 'Fleur'),
  _PlantChoice('🍓', 'Fraise'),
  _PlantChoice('🪴', 'Plante'),
  _PlantChoice('🌳', 'Arbre'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.api,
    required this.initialGreenhouse,
    required this.initialDisplayName,
    required this.initialPlantEmoji,
    required this.onIdentityChanged,
    required this.onLogout,
    super.key,
  });

  final ApiClient api;
  final Greenhouse initialGreenhouse;
  final String initialDisplayName;
  final String initialPlantEmoji;
  final void Function(String greenhouseId, String name, String emoji)
      onIdentityChanged;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Greenhouse greenhouse = widget.initialGreenhouse;
  late String displayName = widget.initialDisplayName;
  late String plantEmoji = widget.initialPlantEmoji;
  SensorReading? latest;
  List<SensorReading> history = [];
  List<Routine> routines = [];
  bool loading = true;
  bool cameraActive = false;
  int irrigationAlertDelaySeconds = 120;
  int page = 0;
  String? error;
  Timer? _irrigationAlertTimer;
  bool _irrigationAlertOpen = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadIrrigationAlertDelay();
  }

  @override
  void dispose() {
    _irrigationAlertTimer?.cancel();
    if (greenhouse.actuators['irrigation']?.state ?? false) {
      unawaited(
        widget.api.setActuator(greenhouse.id, 'irrigation', false),
      );
    }
    super.dispose();
  }

  Future<void> _loadIrrigationAlertDelay() async {
    final preferences = await SharedPreferences.getInstance();
    final savedSeconds = preferences.getInt(
      'irrigation_alert_delay_seconds_${greenhouse.id}',
    );
    final legacyMinutes = preferences.getInt(
      'irrigation_alert_delay_${greenhouse.id}',
    );
    final saved =
        savedSeconds ?? (legacyMinutes == null ? null : legacyMinutes * 60);
    if (!mounted ||
        saved == null ||
        ![10, 30, 60, 120, 300, 600].contains(saved)) {
      return;
    }
    setState(() => irrigationAlertDelaySeconds = saved);
  }

  Future<void> _refresh() async {
    setState(() => error = null);
    try {
      final results = await Future.wait([
        widget.api.getGreenhouse(greenhouse.id),
        widget.api.latestReading(greenhouse.id),
        widget.api.readings(greenhouse.id),
        widget.api.routines(greenhouse.id),
      ]);
      setState(() {
        greenhouse = results[0] as Greenhouse;
        latest = results[1] as SensorReading?;
        history = results[2] as List<SensorReading>;
        routines = results[3] as List<Routine>;
      });
    } catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _collectAndRefresh() async {
    String? collectionError;
    try {
      await widget.api.collectReading(greenhouse.id);
    } catch (exception) {
      collectionError = exception.toString();
    }

    await _refresh();
    if (!mounted || collectionError == null) return;
    setState(() => error = 'Lecture impossible : $collectionError');
  }

  Future<void> _toggleActuator(String name, bool state) async {
    try {
      final actuator = await widget.api.setActuator(
        greenhouse.id,
        name,
        state,
      );
      if (!mounted) return;
      setState(() => greenhouse = greenhouse.withActuator(name, actuator));
      if (name == 'irrigation') {
        state
            ? _scheduleIrrigationSafetyCheck()
            : _irrigationAlertTimer?.cancel();
      }
    } catch (exception) {
      _message(exception.toString());
    }
  }

  Future<void> _setIrrigationAlertDelay(int seconds) async {
    setState(() => irrigationAlertDelaySeconds = seconds);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      'irrigation_alert_delay_seconds_${greenhouse.id}',
      seconds,
    );
    if (greenhouse.actuators['irrigation']?.state ?? false) {
      _scheduleIrrigationSafetyCheck();
      _message(
        'Nouvelle alerte programmée dans '
        '${_formatIrrigationDelay(seconds)}.',
      );
    }
  }

  Future<void> _editGreenhouseIdentity() async {
    final draft = await showModalBottomSheet<_GreenhouseIdentityDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GreenhouseIdentitySheet(
        initialName: displayName,
        initialEmoji: plantEmoji,
      ),
    );
    if (!mounted || draft == null) return;

    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString('greenhouse_name_${greenhouse.id}', draft.name),
      preferences.setString(
        'greenhouse_plant_emoji_${greenhouse.id}',
        draft.emoji,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      displayName = draft.name;
      plantEmoji = draft.emoji;
    });
    widget.onIdentityChanged(greenhouse.id, draft.name, draft.emoji);
    _message('Bandeau de la serre mis à jour.');
  }

  void _scheduleIrrigationSafetyCheck() {
    _irrigationAlertTimer?.cancel();
    _irrigationAlertTimer = Timer(
      Duration(seconds: irrigationAlertDelaySeconds),
      _showIrrigationSafetyPrompt,
    );
  }

  Future<void> _showIrrigationSafetyPrompt() async {
    if (!mounted ||
        _irrigationAlertOpen ||
        !(greenhouse.actuators['irrigation']?.state ?? false)) {
      return;
    }

    _irrigationAlertOpen = true;
    final decision = await showDialog<_IrrigationSafetyDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _IrrigationSafetyDialog(),
    );
    _irrigationAlertOpen = false;
    if (!mounted || decision == null) return;

    if (decision == _IrrigationSafetyDecision.continueWatering) {
      _scheduleIrrigationSafetyCheck();
      _message(
        'Arrosage maintenu. Nouvelle vérification dans '
        '${_formatIrrigationDelay(irrigationAlertDelaySeconds)}.',
      );
      return;
    }

    await _toggleActuator('irrigation', false);
    if (!mounted) return;
    _message(
      decision == _IrrigationSafetyDecision.timedOut
          ? 'Arrosage coupé automatiquement pour économiser l’eau.'
          : 'Arrosage arrêté.',
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Aperçu', 'Mesures', 'Automatisations'];
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[page]),
        actions: [
          IconButton(
            onPressed: _collectAndRefresh,
            tooltip: 'Actualiser',
            style: IconButton.styleFrom(
              foregroundColor: colors.accent,
              backgroundColor: colors.accent.withValues(alpha: 0.1),
              disabledForegroundColor: colors.muted,
              disabledBackgroundColor: colors.surfaceSoft,
            ),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: Text('Se déconnecter'),
              ),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: colors.accent,
              backgroundColor: colors.surface,
              onRefresh: _collectAndRefresh,
              child: IndexedStack(
                index: page,
                children: [
                  OverviewPage(
                    api: widget.api,
                    greenhouse: greenhouse,
                    displayName: displayName,
                    plantEmoji: plantEmoji,
                    reading: latest,
                    error: error,
                    onToggle: _toggleActuator,
                    cameraActive: cameraActive,
                    onCameraToggle: () => setState(
                      () => cameraActive = !cameraActive,
                    ),
                    irrigationAlertDelaySeconds: irrigationAlertDelaySeconds,
                    onIrrigationAlertDelayChanged: _setIrrigationAlertDelay,
                    onEditIdentity: _editGreenhouseIdentity,
                  ),
                  ReadingsPage(readings: history),
                  RoutinesPage(
                    routines: routines,
                    greenhouseId: greenhouse.id,
                    api: widget.api,
                    onChanged: _refresh,
                    showMessage: _message,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.navigation,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          top: false,
          child: FBottomNavigationBar(
            index: page,
            onChange: (value) => setState(() => page = value),
            children: const [
              FBottomNavigationBarItem(
                icon: Icon(FLucideIcons.layoutDashboard),
                label: Text('Aperçu'),
              ),
              FBottomNavigationBarItem(
                icon: Icon(FLucideIcons.chartNoAxesCombined),
                label: Text('Mesures'),
              ),
              FBottomNavigationBarItem(
                icon: Icon(FLucideIcons.timerReset),
                label: Text('Automatisations'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: page == 2
          ? FloatingActionButton.extended(
              backgroundColor: colors.accent,
              foregroundColor: appOnAccent(colors),
              onPressed: () async {
                final created = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => RoutineForm(
                    api: widget.api,
                    greenhouseId: greenhouse.id,
                  ),
                );
                if (created == true) _refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            )
          : null,
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    required this.api,
    required this.greenhouse,
    required this.displayName,
    required this.plantEmoji,
    required this.reading,
    required this.error,
    required this.onToggle,
    required this.cameraActive,
    required this.onCameraToggle,
    required this.irrigationAlertDelaySeconds,
    required this.onIrrigationAlertDelayChanged,
    required this.onEditIdentity,
    super.key,
  });

  final ApiClient api;
  final Greenhouse greenhouse;
  final String displayName;
  final String plantEmoji;
  final SensorReading? reading;
  final String? error;
  final Future<void> Function(String, bool) onToggle;
  final bool cameraActive;
  final VoidCallback onCameraToggle;
  final int irrigationAlertDelaySeconds;
  final ValueChanged<int> onIrrigationAlertDelayChanged;
  final VoidCallback onEditIdentity;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        GestureDetector(
          onTap: onEditIdentity,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: colors.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Text(
                    plantEmoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colors.foreground,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        greenhouse.online
                            ? 'En ligne · Appuyez pour modifier'
                            : 'Hors ligne · Appuyez pour modifier',
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Icon(
                      greenhouse.online ? Icons.wifi : Icons.wifi_off,
                      color: colors.accent,
                    ),
                    const SizedBox(height: 9),
                    Icon(
                      FLucideIcons.pencil,
                      color: colors.muted,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text(
          'Climat actuel',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.92,
          children: [
            DashboardGaugeCard(
              icon: Icons.thermostat,
              label: 'Température',
              value: reading?.temperature,
              unit: '°C',
              minimum: 5,
              maximum: 40,
              idealMinimum: 18,
              idealMaximum: 26,
              color: const Color(0xffe76f51),
            ),
            DashboardGaugeCard(
              icon: Icons.water_drop_outlined,
              label: 'Humidité air',
              value: reading?.airHumidity,
              unit: '%',
              minimum: 20,
              maximum: 100,
              idealMinimum: 55,
              idealMaximum: 75,
              color: const Color(0xff3282b8),
            ),
            DashboardGaugeCard(
              icon: Icons.grass,
              label: 'Humidité sol',
              value: reading?.soilHumidity,
              unit: '%',
              minimum: 0,
              maximum: 100,
              idealMinimum: 45,
              idealMaximum: 65,
              color: const Color(0xff588157),
            ),
            DashboardGaugeCard(
              icon: Icons.light_mode_outlined,
              label: 'Luminosité',
              value: reading?.lightLevel,
              unit: 'lx',
              minimum: 0,
              maximum: 1500,
              idealMinimum: 500,
              idealMaximum: 1000,
              color: const Color(0xffe9c46a),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          'Caméra',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Le direct reste coupé tant que vous ne l’ouvrez pas.',
          style: TextStyle(color: Color(0xff7f8988), fontSize: 13),
        ),
        const SizedBox(height: 12),
        CameraFeedCard(
          api: api,
          active: cameraActive,
          greenhouseId: greenhouse.id,
          onToggle: onCameraToggle,
        ),
        const SizedBox(height: 26),
        Text(
          'Commandes',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ActuatorTile(
          icon: Icons.lightbulb_outline,
          title: 'Éclairage',
          subtitle: 'Lampes de croissance',
          value: greenhouse.actuators['light']?.state ?? false,
          onChanged: (value) => onToggle('light', value),
        ),
        const SizedBox(height: 10),
        IrrigationControlCard(
          icon: Icons.water,
          title: 'Arrosage',
          subtitle: 'Pompe d’irrigation',
          value: greenhouse.actuators['irrigation']?.state ?? false,
          alertDelaySeconds: irrigationAlertDelaySeconds,
          onDelayChanged: onIrrigationAlertDelayChanged,
          onChanged: (value) => onToggle('irrigation', value),
        ),
        const SizedBox(height: 10),
        ActuatorTile(
          icon: Icons.air,
          title: 'Aération',
          subtitle: 'Ouverture de la fenêtre',
          value: greenhouse.actuators['ventilation']?.state ?? false,
          onChanged: (value) => onToggle('ventilation', value),
        ),
      ],
    );
  }
}

class _PlantChoice {
  const _PlantChoice(this.emoji, this.label);

  final String emoji;
  final String label;
}

class _GreenhouseIdentityDraft {
  const _GreenhouseIdentityDraft({
    required this.name,
    required this.emoji,
  });

  final String name;
  final String emoji;
}

class _GreenhouseIdentitySheet extends StatefulWidget {
  const _GreenhouseIdentitySheet({
    required this.initialName,
    required this.initialEmoji,
  });

  final String initialName;
  final String initialEmoji;

  @override
  State<_GreenhouseIdentitySheet> createState() =>
      _GreenhouseIdentitySheetState();
}

class _GreenhouseIdentitySheetState extends State<_GreenhouseIdentitySheet> {
  late final TextEditingController nameController =
      TextEditingController(text: widget.initialName);
  late String selectedEmoji = widget.initialEmoji;

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _GreenhouseIdentityDraft(name: name, emoji: selectedEmoji),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Personnaliser la serre',
                style: TextStyle(
                  color: colors.foreground,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ces informations restent enregistrées sur cet appareil.',
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: nameController,
                maxLength: 36,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nom de la serre',
                  hintText: 'Ex. Serre des tomates',
                  prefixIcon: Icon(FLucideIcons.pencil),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pictogramme',
                style: TextStyle(
                  color: colors.foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                itemCount: _plantChoices.length,
                itemBuilder: (context, index) {
                  final choice = _plantChoices[index];
                  final selected = choice.emoji == selectedEmoji;
                  return GestureDetector(
                    onTap: () => setState(() => selectedEmoji = choice.emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.accent.withValues(alpha: 0.17)
                            : colors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? colors.accent : colors.border,
                          width: selected ? 1.8 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            choice.emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            choice.label,
                            style: TextStyle(
                              color:
                                  selected ? colors.foreground : colors.muted,
                              fontSize: 10,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: const Color(0xff10201b),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: nameController.text.trim().isEmpty ? null : _save,
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CameraFeedCard extends StatefulWidget {
  const CameraFeedCard({
    required this.api,
    required this.active,
    required this.greenhouseId,
    required this.onToggle,
    super.key,
  });

  final ApiClient api;
  final bool active;
  final String greenhouseId;
  final VoidCallback onToggle;

  @override
  State<CameraFeedCard> createState() => _CameraFeedCardState();
}

class _CameraFeedCardState extends State<CameraFeedCard> {
  static const _maximumBufferSize = 5 * 1024 * 1024;

  final List<int> _buffer = [];
  http.Client? _client;
  Timer? _firstFrameTimer;
  Uint8List? _frame;
  String? _error;
  bool _connecting = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_startStream());
  }

  @override
  void didUpdateWidget(covariant CameraFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final greenhouseChanged = oldWidget.greenhouseId != widget.greenhouseId;
    if (widget.active && (!oldWidget.active || greenhouseChanged)) {
      unawaited(_startStream());
    } else if (!widget.active && oldWidget.active) {
      _stopStream(reset: true);
    }
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  Future<void> _startStream() async {
    _stopStream(reset: true);
    final generation = ++_generation;
    final client = http.Client();
    _client = client;
    if (mounted) {
      setState(() {
        _connecting = true;
        _error = null;
      });
    }

    try {
      final response = await client
          .send(widget.api.cameraStreamRequest(widget.greenhouseId))
          .timeout(widget.api.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw ApiException(
          response.statusCode == 401
              ? 'Session expirée. Reconnectez-vous.'
              : 'Flux refusé par l’API (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }

      _firstFrameTimer = Timer(widget.api.requestTimeout, () {
        if (!mounted || generation != _generation || _frame != null) return;
        setState(() {
          _connecting = false;
          _error = 'Aucune image reçue depuis la caméra.';
        });
        client.close();
      });

      await for (final chunk in response.stream) {
        if (!mounted || generation != _generation || !widget.active) {
          break;
        }
        final frame = _extractLatestFrame(chunk);
        if (frame == null) continue;
        _firstFrameTimer?.cancel();
        setState(() {
          _frame = frame;
          _connecting = false;
          _error = null;
        });
      }

      if (mounted &&
          generation == _generation &&
          widget.active &&
          _frame == null &&
          _error == null) {
        setState(() {
          _connecting = false;
          _error = 'Le flux caméra a été interrompu.';
        });
      }
    } on TimeoutException {
      _showStreamError(
        generation,
        'La caméra ne répond pas après '
        '${widget.api.requestTimeout.inSeconds} secondes.',
      );
    } on ApiException catch (exception) {
      _showStreamError(generation, exception.message);
    } on http.ClientException catch (exception) {
      _showStreamError(
        generation,
        'Connexion caméra impossible : ${exception.message}',
      );
    } catch (_) {
      _showStreamError(generation, 'Flux caméra indisponible.');
    }
  }

  void _showStreamError(int generation, String message) {
    if (!mounted || generation != _generation || !widget.active) return;
    setState(() {
      _connecting = false;
      _error = message;
    });
  }

  void _stopStream({bool reset = false}) {
    _generation++;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    _client?.close();
    _client = null;
    _buffer.clear();
    if (reset) {
      _frame = null;
      _error = null;
      _connecting = false;
    }
  }

  Uint8List? _extractLatestFrame(List<int> chunk) {
    _buffer.addAll(chunk);
    Uint8List? latestFrame;

    while (true) {
      final start = _jpegMarkerIndex(0xff, 0xd8);
      if (start < 0) {
        if (_buffer.length > 1) {
          final lastByte = _buffer.last;
          _buffer
            ..clear()
            ..addAll(lastByte == 0xff ? [lastByte] : const []);
        }
        break;
      }

      final end = _jpegMarkerIndex(0xff, 0xd9, start + 2);
      if (end < 0) {
        if (start > 0) _buffer.removeRange(0, start);
        if (_buffer.length > _maximumBufferSize) _buffer.clear();
        break;
      }

      latestFrame = Uint8List.fromList(_buffer.sublist(start, end + 2));
      _buffer.removeRange(0, end + 2);
    }

    return latestFrame;
  }

  int _jpegMarkerIndex(int first, int second, [int start = 0]) {
    for (var index = start; index < _buffer.length - 1; index++) {
      if (_buffer[index] == first && _buffer[index + 1] == second) {
        return index;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onToggle,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 210,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              child: widget.active ? _activeView() : _standbyView(context),
            ),
          ),
        ),
      );

  Widget _standbyView(BuildContext context) {
    final colors = context.appColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('standby'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xff151c1d), Color(0xff090d0e)]
              : const [Color(0xffe5eee8), Color(0xffd8e5dd)],
        ),
        border: Border.all(color: colors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CameraGridPainter(
                color: dark
                    ? const Color(0x0dffffff)
                    : colors.foreground.withValues(alpha: 0.07),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _CameraPlayButton(),
                const SizedBox(height: 13),
                Text(
                  'Ouvrir le direct',
                  style: TextStyle(
                    color: colors.foreground,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Appuyez pour activer la caméra',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            top: 14,
            child: const _CameraBadge(
              color: Color(0xff72817a),
              label: 'EN VEILLE',
              useThemeSurface: true,
            ),
          ),
          Positioned(
            right: 14,
            top: 14,
            child: Icon(
              FLucideIcons.video,
              color: colors.muted,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeView() {
    if (_error != null) return _errorView();
    if (_frame == null || _connecting) return _connectingView();
    return _liveView(_frame!);
  }

  Widget _connectingView() => Container(
        key: const ValueKey('camera-connecting'),
        color: const Color(0xff090d0e),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xff69e1c1)),
            SizedBox(height: 14),
            Text(
              'Connexion à la caméra…',
              style: TextStyle(
                color: Color(0xffedf1f0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _errorView() => Container(
        key: const ValueKey('camera-error'),
        color: const Color(0xff090d0e),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              FLucideIcons.videoOff,
              color: Color(0xffff8a7a),
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xffedf1f0),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Touchez pour fermer, puis rouvrez le direct.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff9aa5a2), fontSize: 11),
            ),
          ],
        ),
      );

  Widget _liveView(Uint8List frame) {
    return Stack(
      key: const ValueKey('live'),
      fit: StackFit.expand,
      children: [
        Image.memory(
          frame,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x12000000), Color(0xb8000000)],
            ),
          ),
        ),
        const Positioned(
          left: 14,
          top: 14,
          child: _CameraBadge(
            color: Color(0xffff5f5f),
            label: 'DIRECT',
          ),
        ),
        const Positioned(
          right: 14,
          top: 14,
          child: _CameraStopButton(),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Row(
            children: [
              const Icon(
                FLucideIcons.wifi,
                color: Color(0xff69e1c1),
                size: 17,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Flux Raspberry · qualité auto',
                  style: TextStyle(
                    color: Color(0xffd3dad9),
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${DateTime.now().hour.toString().padLeft(2, '0')}:'
                '${DateTime.now().minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Color(0xffaeb7b6),
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraBadge extends StatelessWidget {
  const _CameraBadge({
    required this.color,
    required this.label,
    this.useThemeSurface = false,
  });

  final Color color;
  final String label;
  final bool useThemeSurface;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: useThemeSurface
            ? colors.surface.withValues(alpha: 0.82)
            : const Color(0xb8090d0e),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: useThemeSurface ? colors.border : const Color(0x22ffffff),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color:
                  useThemeSurface ? colors.foreground : const Color(0xffedf1f0),
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPlayButton extends StatelessWidget {
  const _CameraPlayButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: colors.accent),
      ),
      child: Icon(
        FLucideIcons.play,
        color: colors.accent,
        size: 23,
      ),
    );
  }
}

class _CameraStopButton extends StatelessWidget {
  const _CameraStopButton();

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xb8090d0e),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x29ffffff)),
        ),
        child: const Icon(
          FLucideIcons.pause,
          color: Colors.white,
          size: 17,
        ),
      );
}

class _CameraGridPainter extends CustomPainter {
  const _CameraGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const spacing = 32.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CameraGridPainter oldDelegate) =>
      color != oldDelegate.color;
}

class DashboardGaugeCard extends StatelessWidget {
  const DashboardGaugeCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.minimum,
    required this.maximum,
    required this.idealMinimum,
    required this.idealMaximum,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final double? value;
  final String unit;
  final double minimum;
  final double maximum;
  final double idealMinimum;
  final double idealMaximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final status = _status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DashboardGaugePainter(
                        value: value,
                        minimum: minimum,
                        maximum: maximum,
                        idealMinimum: idealMinimum,
                        idealMaximum: idealMaximum,
                        accentColor: color,
                        idealColor: colors.accent,
                        trackColor: colors.border,
                        tickColor: colors.muted,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 7,
                    child: Text(
                      '$_formattedValue $unit',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 2,
                    bottom: 8,
                    child: Text(
                      _rangeValue(minimum),
                      style: TextStyle(color: colors.muted, fontSize: 8),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 8,
                    child: Text(
                      _rangeValue(maximum),
                      style: TextStyle(color: colors.muted, fontSize: 8),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: status.color(colors),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${status.label} · idéal ${_rangeValue(idealMinimum)}–'
                    '${_rangeValue(idealMaximum)} $unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _formattedValue {
    if (value == null) return '—';
    if (unit == 'lx') return value!.round().toString();
    return value!.toStringAsFixed(1);
  }

  String _rangeValue(double rangeValue) => rangeValue.round().toString();

  _GaugeStatus get _status {
    if (value == null) return _GaugeStatus.unavailable;
    if (value! < idealMinimum) return _GaugeStatus.tooLow;
    if (value! > idealMaximum) return _GaugeStatus.tooHigh;
    return _GaugeStatus.ideal;
  }
}

enum _GaugeStatus {
  ideal,
  tooLow,
  tooHigh,
  unavailable;

  String get label => switch (this) {
        ideal => 'Zone idéale',
        tooLow => 'Trop bas',
        tooHigh => 'Trop haut',
        unavailable => 'Indisponible',
      };

  Color color(AppColors colors) => switch (this) {
        ideal => colors.accent,
        tooLow => const Color(0xff4ca6d8),
        tooHigh => const Color(0xffe9875b),
        unavailable => colors.muted,
      };
}

class _DashboardGaugePainter extends CustomPainter {
  const _DashboardGaugePainter({
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.idealMinimum,
    required this.idealMaximum,
    required this.accentColor,
    required this.idealColor,
    required this.trackColor,
    required this.tickColor,
  });

  final double? value;
  final double minimum;
  final double maximum;
  final double idealMinimum;
  final double idealMaximum;
  final Color accentColor;
  final Color idealColor;
  final Color trackColor;
  final Color tickColor;

  static const _startAngle = math.pi * 0.75;
  static const _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.48);
    final radius = math.min(size.width * 0.42, size.height * 0.43);
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, _startAngle, _sweepAngle, false, trackPaint);

    final idealStart = _position(idealMinimum);
    final idealEnd = _position(idealMaximum);
    final idealPaint = Paint()
      ..color = idealColor.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      arcRect,
      _startAngle + (_sweepAngle * idealStart),
      _sweepAngle * (idealEnd - idealStart),
      false,
      idealPaint,
    );

    final tickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.65)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index <= 10; index++) {
      final angle = _startAngle + (_sweepAngle * index / 10);
      final isMajor = index % 5 == 0;
      final outer = Offset(
        center.dx + math.cos(angle) * (radius + 1),
        center.dy + math.sin(angle) * (radius + 1),
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - (isMajor ? 10 : 6)),
        center.dy + math.sin(angle) * (radius - (isMajor ? 10 : 6)),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    if (value == null) return;
    final valuePosition = _position(value!);
    final valueAngle = _startAngle + (_sweepAngle * valuePosition);
    final needlePaint = Paint()
      ..color = accentColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final needleEnd = Offset(
      center.dx + math.cos(valueAngle) * (radius - 15),
      center.dy + math.sin(valueAngle) * (radius - 15),
    );
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 5.5, Paint()..color = accentColor);
    canvas.drawCircle(
      center,
      2.2,
      Paint()..color = const Color(0xfff5f7f6),
    );
  }

  double _position(double current) =>
      ((current - minimum) / (maximum - minimum)).clamp(0.0, 1.0);

  @override
  bool shouldRepaint(covariant _DashboardGaugePainter oldDelegate) =>
      value != oldDelegate.value ||
      minimum != oldDelegate.minimum ||
      maximum != oldDelegate.maximum ||
      idealMinimum != oldDelegate.idealMinimum ||
      idealMaximum != oldDelegate.idealMaximum ||
      accentColor != oldDelegate.accentColor ||
      idealColor != oldDelegate.idealColor ||
      trackColor != oldDelegate.trackColor ||
      tickColor != oldDelegate.tickColor;
}

class IrrigationControlCard extends StatelessWidget {
  const IrrigationControlCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.alertDelaySeconds,
    required this.onDelayChanged,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final int alertDelaySeconds;
  final ValueChanged<int> onDelayChanged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colors.accent.withValues(alpha: 0.13),
              child: Icon(icon, color: colors.accent),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              value ? 'Pompe active · protection activée' : subtitle,
            ),
            value: value,
            activeThumbColor: colors.accent,
            activeTrackColor: colors.accent.withValues(alpha: 0.34),
            inactiveThumbColor: colors.muted,
            inactiveTrackColor: colors.surfaceSoft,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            onChanged: onChanged,
          ),
          Divider(height: 1, color: colors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 10, 11),
            child: Row(
              children: [
                Icon(
                  FLucideIcons.shieldCheck,
                  color: colors.accent,
                  size: 19,
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Délai avant alerte',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Puis arrêt automatique après 10 s',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<int>(
                  initialValue: alertDelaySeconds,
                  tooltip: 'Modifier le délai de sécurité',
                  onSelected: onDelayChanged,
                  itemBuilder: (_) => [10, 30, 60, 120, 300, 600]
                      .map(
                        (seconds) => PopupMenuItem<int>(
                          value: seconds,
                          child: Text(
                            _formatIrrigationDelay(seconds),
                          ),
                        ),
                      )
                      .toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatIrrigationDelay(
                            alertDelaySeconds,
                            compact: true,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(FLucideIcons.chevronDown, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _IrrigationSafetyDecision {
  continueWatering,
  stopNow,
  timedOut,
}

class _IrrigationSafetyDialog extends StatefulWidget {
  const _IrrigationSafetyDialog();

  @override
  State<_IrrigationSafetyDialog> createState() =>
      _IrrigationSafetyDialogState();
}

class _IrrigationSafetyDialogState extends State<_IrrigationSafetyDialog> {
  static const _countdownSeconds = 10;
  int remainingSeconds = _countdownSeconds;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (remainingSeconds <= 1) {
        Navigator.of(context).pop(_IrrigationSafetyDecision.timedOut);
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: CircleAvatar(
          radius: 25,
          backgroundColor: colors.accent.withValues(alpha: 0.16),
          child: Icon(
            FLucideIcons.droplets,
            color: colors.accent,
            size: 25,
          ),
        ),
        title: const Text('Continuer l’arrosage ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pour éviter de gaspiller l’eau ou de noyer les plantes, '
              'la pompe va s’arrêter sans confirmation.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: remainingSeconds / _countdownSeconds,
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
              color: colors.accent,
              backgroundColor: colors.border,
            ),
            const SizedBox(height: 9),
            Text(
              'Arrêt automatique dans $remainingSeconds s',
              style: TextStyle(
                color: colors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: const Color(0xff10201b),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () => Navigator.of(context).pop(
                      _IrrigationSafetyDecision.continueWatering,
                    ),
                    icon: const Icon(FLucideIcons.rotateCw, size: 16),
                    label: const Text('Continuer l’arrosage'),
                  ),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      _IrrigationSafetyDecision.stopNow,
                    ),
                    child: const Text('Couper maintenant'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActuatorTile extends StatelessWidget {
  const ActuatorTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Card(
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: colors.accent.withValues(alpha: 0.13),
          child: Icon(icon, color: colors.accent),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        value: value,
        activeThumbColor: colors.accent,
        activeTrackColor: colors.accent.withValues(alpha: 0.34),
        inactiveThumbColor: colors.muted,
        inactiveTrackColor: colors.surfaceSoft,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        onChanged: onChanged,
      ),
    );
  }
}

class ReadingsPage extends StatelessWidget {
  const ReadingsPage({required this.readings, super.key});
  final List<SensorReading> readings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (readings.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 150),
          Icon(
            Icons.query_stats,
            size: 64,
            color: colors.accent,
          ),
          const SizedBox(height: 12),
          const Center(child: Text('Aucune mesure disponible')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      itemCount: readings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = readings[index];
        final date = item.measuredAt?.toLocal();
        final dateText = date == null
            ? 'Date inconnue'
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} '
                'à ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.accent.withValues(alpha: 0.13),
              child: Icon(Icons.thermostat, color: colors.accent),
            ),
            title: Text(
              '${item.temperature?.toStringAsFixed(1) ?? '—'} °C  ·  '
              '${item.airHumidity?.toStringAsFixed(0) ?? '—'} %',
            ),
            subtitle: Text(
              '$dateText\nSol ${item.soilHumidity?.toStringAsFixed(0) ?? '—'} %  ·  '
              '${item.lightLevel?.toStringAsFixed(0) ?? '—'} lx',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

class RoutinesPage extends StatelessWidget {
  const RoutinesPage({
    required this.routines,
    required this.greenhouseId,
    required this.api,
    required this.onChanged,
    required this.showMessage,
    super.key,
  });

  final List<Routine> routines;
  final String greenhouseId;
  final ApiClient api;
  final VoidCallback onChanged;
  final ValueChanged<String> showMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (routines.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 150),
          Icon(Icons.schedule, size: 64),
          SizedBox(height: 12),
          Center(child: Text('Aucune routine programmée')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      itemCount: routines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final routine = routines[index];
        return Dismissible(
          key: ValueKey(routine.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Supprimer la routine ?'),
              content: Text(routine.name),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          ),
          onDismissed: (_) async {
            try {
              await api.deleteRoutine(greenhouseId, routine.id);
              onChanged();
            } catch (exception) {
              showMessage(exception.toString());
              onChanged();
            }
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: Card(
            child: SwitchListTile(
              secondary: CircleAvatar(
                backgroundColor: colors.accent.withValues(alpha: 0.13),
                child: Icon(
                  _actuatorIcon(routine.actuator),
                  color: colors.accent,
                ),
              ),
              title: Text(
                routine.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${routine.time}  ·  ${_dayNames(routine.days)}\n'
                '${_actuatorName(routine.actuator)} pendant '
                '${_duration(routine.durationSeconds)}',
              ),
              isThreeLine: true,
              value: routine.enabled,
              activeThumbColor: colors.accent,
              activeTrackColor: colors.accent.withValues(alpha: 0.34),
              inactiveThumbColor: colors.muted,
              inactiveTrackColor: colors.surfaceSoft,
              trackOutlineColor:
                  const WidgetStatePropertyAll(Colors.transparent),
              onChanged: (value) async {
                try {
                  await api.toggleRoutine(
                    greenhouseId,
                    routine,
                    value,
                  );
                  onChanged();
                } catch (exception) {
                  showMessage(exception.toString());
                }
              },
            ),
          ),
        );
      },
    );
  }

  static IconData _actuatorIcon(String actuator) => switch (actuator) {
        'light' => Icons.lightbulb_outline,
        'ventilation' => Icons.air,
        _ => Icons.water,
      };

  static String _actuatorName(String actuator) => switch (actuator) {
        'light' => 'Éclairage',
        'ventilation' => 'Aération',
        _ => 'Arrosage',
      };

  static String _dayNames(List<int> days) {
    if (days.length == 7) return 'Tous les jours';
    const names = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    return days.map((day) => names[day]).join(', ');
  }

  static String _duration(int seconds) {
    if (seconds >= 3600) return '${seconds ~/ 3600} h';
    if (seconds >= 60) return '${seconds ~/ 60} min';
    return '$seconds s';
  }
}

class RoutineForm extends StatefulWidget {
  const RoutineForm({
    required this.api,
    required this.greenhouseId,
    super.key,
  });

  final ApiClient api;
  final String greenhouseId;

  @override
  State<RoutineForm> createState() => _RoutineFormState();
}

class _RoutineFormState extends State<RoutineForm> {
  final name = TextEditingController(text: 'Arrosage du matin');
  final duration = TextEditingController(text: '2');
  String actuator = 'irrigation';
  TimeOfDay time = const TimeOfDay(hour: 7, minute: 30);
  final Set<int> days = {1, 2, 3, 4, 5};
  bool loading = false;
  String? error;

  Future<void> _save() async {
    if (name.text.trim().length < 2 || days.isEmpty) {
      setState(() => error = 'Indiquez un nom et au moins un jour.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final minutes = int.tryParse(duration.text) ?? 1;
      await widget.api.createRoutine(widget.greenhouseId, {
        'name': name.text.trim(),
        'actuator': actuator,
        'time':
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        'days': days.toList()..sort(),
        'durationSeconds': minutes * 60,
        'value': 100,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const dayNames = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];
    final colors = context.appColors;
    final primaryForeground = appOnAccent(colors);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          22,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nouvelle routine',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: actuator,
                decoration: const InputDecoration(labelText: 'Action'),
                items: const [
                  DropdownMenuItem(
                    value: 'irrigation',
                    child: Text('Arrosage'),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text('Éclairage'),
                  ),
                  DropdownMenuItem(
                    value: 'ventilation',
                    child: Text('Aération'),
                  ),
                ],
                onChanged: (value) => setState(() => actuator = value!),
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: colors.surfaceSoft,
                leading: Icon(Icons.schedule, color: colors.accent),
                title: const Text('Heure de début'),
                trailing: Text(
                  time.format(context),
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  final selected = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (selected != null) setState(() => time = selected);
                },
              ),
              const SizedBox(height: 18),
              const Text(
                'Jours',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                children: List.generate(
                  7,
                  (index) {
                    final selected = days.contains(index);
                    return FilterChip(
                      label: Text(
                        dayNames[index],
                        style: TextStyle(
                          color:
                              selected ? primaryForeground : colors.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      selected: selected,
                      selectedColor: colors.accent,
                      backgroundColor: colors.surfaceSoft,
                      checkmarkColor: primaryForeground,
                      side: BorderSide(
                        color: selected ? colors.accent : colors.border,
                      ),
                      onSelected: (value) => setState(() {
                        value ? days.add(index) : days.remove(index);
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durée en minutes',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: loading ? null : _save,
                style: appPrimaryButtonStyle(context),
                child: loading
                    ? SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryForeground,
                        ),
                      )
                    : const Text('Créer la routine'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
