import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'greenhouse_list_screen.dart';
import 'mock_api_client.dart';
import 'models.dart';
import 'serial_number_input.dart';

const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:3000/api',
);
const useMockData = bool.fromEnvironment('USE_MOCK_DATA', defaultValue: true);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HaricultureApp());
}

class HaricultureApp extends StatefulWidget {
  const HaricultureApp({super.key});

  @override
  State<HaricultureApp> createState() => _HaricultureAppState();
}

class _HaricultureAppState extends State<HaricultureApp> {
  final ApiClient api =
      useMockData ? MockApiClient() : ApiClient(baseUrl: apiUrl);
  bool loading = true;
  bool authenticated = false;
  bool darkMode = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final preferences = await SharedPreferences.getInstance();
    api.token = preferences.getString('auth_token');
    setState(() {
      authenticated = api.token != null;
      darkMode = preferences.getBool('dark_mode') ?? true;
      loading = false;
    });
  }

  Future<void> _setDarkMode(bool value) async {
    setState(() => darkMode = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('dark_mode', value);
  }

  Future<void> _authenticated(String token) async {
    api.token = token;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('auth_token', token);
    setState(() => authenticated = true);
  }

  Future<void> _logout() async {
    api.token = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('auth_token');
    setState(() => authenticated = false);
  }

  @override
  Widget build(BuildContext context) {
    final foruiTheme =
        darkMode ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch;
    final appColors = darkMode ? AppColors.dark : AppColors.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hariculture',
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      theme: foruiTheme.toApproximateMaterialTheme().copyWith(
            scaffoldBackgroundColor: appColors.background,
            extensions: [appColors],
            appBarTheme: AppBarTheme(
              backgroundColor: appColors.background,
              foregroundColor: appColors.foreground,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              color: appColors.surface,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(22)),
                side: BorderSide(color: appColors.border),
              ),
            ),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide.none,
              ),
            ),
          ),
      builder: (context, child) => FTheme(
        data: foruiTheme,
        platform: FPlatformVariant.iOS,
        child: FToaster(
          child: FTooltipGroup(child: child!),
        ),
      ),
      home: loading
          ? const SplashScreen()
          : authenticated
              ? GreenhouseLoader(
                  api: api,
                  onLogout: _logout,
                  darkMode: darkMode,
                  onThemeChanged: _setDarkMode,
                )
              : AuthScreen(api: api, onAuthenticated: _authenticated),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.api,
    required this.onAuthenticated,
    super.key,
  });

  final ApiClient api;
  final ValueChanged<String> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late final name = TextEditingController(text: 'Camille Jardin');
  late final email = TextEditingController(
    text: widget.api is MockApiClient ? 'demo@hariculture.fr' : '',
  );
  late final password = TextEditingController(
    text: widget.api is MockApiClient ? 'demo1234' : '',
  );
  bool register = false;
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final token = register
          ? await widget.api.register(name.text, email.text, password.text)
          : await widget.api.login(email.text, password.text);
      widget.onAuthenticated(token);
    } catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.eco_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Cultivez plus\nsereinement.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.api is MockApiClient
                          ? 'Une démo complète, prête à explorer sans matériel.'
                          : 'Votre serre, ses mesures et ses routines dans votre poche.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 34),
                    if (register) ...[
                      TextField(
                        controller: name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Prénom et nom',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Adresse email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: loading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              register ? 'Créer mon compte' : 'Se connecter'),
                    ),
                    if (widget.api is MockApiClient)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Mode démo local · aucune donnée n’est envoyée',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        register = !register;
                        error = null;
                      }),
                      child: Text(
                        register
                            ? 'J’ai déjà un compte'
                            : 'Créer un nouveau compte',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class GreenhouseLoader extends StatefulWidget {
  const GreenhouseLoader({
    required this.api,
    required this.onLogout,
    required this.darkMode,
    required this.onThemeChanged,
    super.key,
  });

  final ApiClient api;
  final VoidCallback onLogout;
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<GreenhouseLoader> createState() => _GreenhouseLoaderState();
}

class _GreenhouseLoaderState extends State<GreenhouseLoader> {
  bool loading = true;
  List<Greenhouse>? greenhouses;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final greenhouses = await widget.api.getGreenhouses();
      setState(() {
        this.greenhouses = greenhouses.isEmpty ? null : greenhouses;
        loading = false;
      });
    } catch (exception) {
      if (exception is ApiException && exception.statusCode == 401) {
        widget.onLogout();
        return;
      }
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SplashScreen();
    if (error != null) {
      return ErrorScreen(
        message: error!,
        onRetry: () {
          setState(() {
            loading = true;
            error = null;
          });
          _load();
        },
        onLogout: widget.onLogout,
      );
    }
    if (greenhouses == null) {
      return PairScreen(
        api: widget.api,
        onPaired: (value) => setState(() => greenhouses = [value]),
        onLogout: widget.onLogout,
      );
    }
    return GreenhouseListScreen(
      api: widget.api,
      greenhouses: greenhouses!,
      onLogout: widget.onLogout,
      darkMode: widget.darkMode,
      onThemeChanged: widget.onThemeChanged,
    );
  }
}

class PairScreen extends StatefulWidget {
  const PairScreen({
    required this.api,
    required this.onPaired,
    required this.onLogout,
    super.key,
  });

  final ApiClient api;
  final ValueChanged<Greenhouse> onPaired;
  final VoidCallback onLogout;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final code = TextEditingController(text: '0000');
  bool loading = false;
  String? error;

  Future<void> _pair() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      widget.onPaired(await widget.api.pairGreenhouse(code.text));
    } catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              onPressed: widget.onLogout,
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  const Icon(Icons.sensors, size: 88),
                  const SizedBox(height: 22),
                  Text(
                    'Associer votre serre',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Saisissez le code à 4 caractères affiché sur votre boîtier Hariculture.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: code,
                    maxLength: 4,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: serialNumberInputFormatters,
                    onChanged: (_) => setState(() => error = null),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold,
                        ),
                    decoration: const InputDecoration(labelText: 'Code'),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: loading || code.text.length != 4 ? null : _pair,
                    icon: const Icon(Icons.link),
                    label: const Text('Associer la serre'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onLogout,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 64),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton(
                    onPressed: onRetry, child: const Text('Réessayer')),
                TextButton(
                  onPressed: onLogout,
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      );
}
