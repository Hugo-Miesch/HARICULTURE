import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'models.dart';
import 'serial_number_input.dart';

// Conservé pour pouvoir réactiver la section sans reconstruire son écran.
const bool _challengesEnabled = false;

class GreenhouseListScreen extends StatefulWidget {
  const GreenhouseListScreen({
    required this.api,
    required this.greenhouses,
    required this.onLogout,
    required this.darkMode,
    required this.onThemeChanged,
    super.key,
  });

  final ApiClient api;
  final List<Greenhouse> greenhouses;
  final VoidCallback onLogout;
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<GreenhouseListScreen> createState() => _GreenhouseListScreenState();
}

class _GreenhouseListScreenState extends State<GreenhouseListScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final List<Greenhouse> greenhouses;
  final Map<String, SensorReading?> readings = {};
  final Map<String, String> greenhouseNames = {};
  final Map<String, String> greenhouseEmojis = {};
  UserProfile? userProfile;
  String? profileError;
  bool loading = true;
  int section = 0;

  @override
  void initState() {
    super.initState();
    greenhouses = List<Greenhouse>.of(widget.greenhouses);
    _loadReadings();
    _loadGreenhouseIdentities();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.api.currentUser();
      if (!mounted) return;
      setState(() {
        userProfile = profile;
        profileError = null;
      });
    } catch (exception) {
      if (!mounted) return;
      if (exception is ApiException && exception.statusCode == 401) {
        widget.onLogout();
        return;
      }
      setState(() => profileError = exception.toString());
    }
  }

  Future<void> _loadGreenhouseIdentities() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final greenhouse in greenhouses) {
        greenhouseNames[greenhouse.id] =
            preferences.getString('greenhouse_name_${greenhouse.id}') ??
                greenhouse.name;
        greenhouseEmojis[greenhouse.id] =
            preferences.getString('greenhouse_plant_emoji_${greenhouse.id}') ??
                (greenhouse.id == 'tropical-greenhouse' ? '🌿' : '🍅');
      }
    });
  }

  void _updateGreenhouseIdentity(
    String greenhouseId,
    String name,
    String emoji,
  ) {
    if (!mounted) return;
    setState(() {
      greenhouseNames[greenhouseId] = name;
      greenhouseEmojis[greenhouseId] = emoji;
    });
  }

  Future<void> _loadReadings() async {
    final values = await Future.wait(
      greenhouses.map(
        (greenhouse) => widget.api.latestReading(greenhouse.id),
      ),
    );
    if (!mounted) return;
    setState(() {
      for (var index = 0; index < greenhouses.length; index++) {
        readings[greenhouses[index].id] = values[index];
      }
      loading = false;
    });
  }

  Future<void> _collectAndLoadReadings() async {
    try {
      await Future.wait(
        greenhouses.map(
          (greenhouse) => widget.api.collectReading(greenhouse.id),
        ),
      );
      await _loadReadings();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lecture impossible : $exception')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accountSection = _challengesEnabled ? 3 : 2;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.background,
      drawer: _AppDrawer(
        section: section,
        gallerySection: 1,
        accountSection: accountSection,
        onSelect: (value) {
          Navigator.of(context).pop();
          setState(() => section = value);
        },
      ),
      body: IndexedStack(
        index: section,
        children: [
          _greenhousesPage(
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          _GalleryPage(
            api: widget.api,
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          if (_challengesEnabled) const _ChallengesPage(),
          _AccountPage(
            profile: userProfile,
            profileError: profileError,
            onRetryProfile: _loadProfile,
            onLogout: widget.onLogout,
            darkMode: widget.darkMode,
            onThemeChanged: widget.onThemeChanged,
            onClearLocalData: () => _clearLocalData(context),
            onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
    );
  }

  Widget _greenhousesPage({required VoidCallback onOpenMenu}) => SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _collectAndLoadReadings,
          color: context.appColors.accent,
          backgroundColor: context.appColors.surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
                sliver: SliverToBoxAdapter(
                  child: _Header(
                    onLogout: widget.onLogout,
                    onOpenMenu: onOpenMenu,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                sliver: SliverList.separated(
                  itemCount: greenhouses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 18),
                  itemBuilder: (context, index) {
                    final greenhouse = greenhouses[index];
                    return _GreenhouseCard(
                      greenhouse: greenhouse,
                      displayName:
                          greenhouseNames[greenhouse.id] ?? greenhouse.name,
                      plantEmoji: greenhouseEmojis[greenhouse.id] ??
                          (greenhouse.id == 'tropical-greenhouse'
                              ? '🌿'
                              : '🍅'),
                      reading: readings[greenhouse.id],
                      loading: loading,
                      imageAsset: index.isEven
                          ? 'assets/images/greenhouse-tomatoes.png'
                          : 'assets/images/greenhouse-tropical.png',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HomeScreen(
                            api: widget.api,
                            initialGreenhouse: greenhouse,
                            initialDisplayName:
                                greenhouseNames[greenhouse.id] ??
                                    greenhouse.name,
                            initialPlantEmoji:
                                greenhouseEmojis[greenhouse.id] ??
                                    (greenhouse.id == 'tropical-greenhouse'
                                        ? '🌿'
                                        : '🍅'),
                            onIdentityChanged: _updateGreenhouseIdentity,
                            onLogout: widget.onLogout,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 2, 22, 42),
                sliver: SliverToBoxAdapter(
                  child: SizedBox(
                    height: 68,
                    child: OutlinedButton.icon(
                      style: appOutlineButtonStyle(
                        context,
                        height: 68,
                        radius: 22,
                      ),
                      icon: const Icon(FLucideIcons.plus, size: 22),
                      onPressed: () => _showAddGreenhouse(context),
                      label: const Text(
                        'Ajouter une serre',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _showAddGreenhouse(BuildContext context) async {
    final greenhouse = await showModalBottomSheet<Greenhouse>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PairGreenhouseSheet(
        api: widget.api,
        pairedGreenhouseIds:
            greenhouses.map((greenhouse) => greenhouse.id).toSet(),
      ),
    );
    if (greenhouse == null || !mounted) return;

    setState(() {
      greenhouses.add(greenhouse);
      greenhouseNames[greenhouse.id] = greenhouse.name;
      greenhouseEmojis[greenhouse.id] = '🌱';
      readings[greenhouse.id] = null;
    });

    final reading = await widget.api.latestReading(greenhouse.id);
    if (mounted) setState(() => readings[greenhouse.id] = reading);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${greenhouse.name} a bien été ajoutée.')),
    );
  }

  Future<void> _clearLocalData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Effacer les données locales ?'),
        content: const Text(
          'Les noms, pictogrammes et délais d’alerte personnalisés seront '
          'réinitialisés. Votre session et votre thème seront conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffc84d4d),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final preferences = await SharedPreferences.getInstance();
    final localKeys = preferences
        .getKeys()
        .where(
          (key) =>
              key.startsWith('greenhouse_name_') ||
              key.startsWith('greenhouse_plant_emoji_') ||
              key.startsWith('irrigation_alert_delay_'),
        )
        .toList();
    await Future.wait(localKeys.map(preferences.remove));
    if (!mounted) return;

    setState(() {
      greenhouseNames
        ..clear()
        ..addEntries(
          greenhouses.map(
            (greenhouse) => MapEntry(greenhouse.id, greenhouse.name),
          ),
        );
      greenhouseEmojis
        ..clear()
        ..addEntries(
          greenhouses.map(
            (greenhouse) => MapEntry(
              greenhouse.id,
              greenhouse.id == 'tropical-greenhouse' ? '🌿' : '🍅',
            ),
          ),
        );
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Données locales réinitialisées.')),
    );
  }
}

class _PairGreenhouseSheet extends StatefulWidget {
  const _PairGreenhouseSheet({
    required this.api,
    required this.pairedGreenhouseIds,
  });

  final ApiClient api;
  final Set<String> pairedGreenhouseIds;

  @override
  State<_PairGreenhouseSheet> createState() => _PairGreenhouseSheetState();
}

class _PairGreenhouseSheetState extends State<_PairGreenhouseSheet> {
  final codeController = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = normalizeSerialNumber(codeController.text);
    if (code.length != 4) {
      setState(() => error = 'Le SN doit contenir exactement 4 caractères.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      final greenhouse = await widget.api.pairGreenhouse(code);
      if (widget.pairedGreenhouseIds.contains(greenhouse.id)) {
        throw ApiException('Cette serre est déjà associée à votre compte.');
      }
      if (mounted) Navigator.of(context).pop(greenhouse);
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception is ApiException && exception.statusCode == 404
              ? 'Création impossible : SN inexistant.'
              : exception.toString();
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    FLucideIcons.scanLine,
                    color: colors.accent,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ajouter une serre',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colors.foreground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Association par numéro de série',
                        style: TextStyle(color: colors.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: loading ? null : () => Navigator.pop(context),
                  tooltip: 'Fermer',
                  icon: const Icon(FLucideIcons.x),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Saisissez les 4 caractères du SN indiqué sur le boîtier de la '
              'serre.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.muted,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: codeController,
              autofocus: true,
              enabled: !loading,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              inputFormatters: serialNumberInputFormatters,
              onChanged: (_) => setState(() => error = null),
              onSubmitted: (_) => _pair(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 14,
                  ),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                filled: true,
                fillColor: colors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: colors.accent, width: 2),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: error == null
                  ? const SizedBox(height: 18)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              FLucideIcons.circleAlert,
                              color: Theme.of(context).colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed:
                    loading || codeController.text.length != 4 ? null : _pair,
                style: appPrimaryButtonStyle(context, height: 56),
                child: loading
                    ? SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: appOnAccent(colors),
                        ),
                      )
                    : const Text(
                        'Associer la serre',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.section,
    required this.gallerySection,
    required this.accountSection,
    required this.onSelect,
  });

  final int section;
  final int gallerySection;
  final int accountSection;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.82,
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: colors.accent.withValues(alpha: 0.32),
                        ),
                      ),
                      child: const Text('🌿', style: TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 13),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HARICULTURE',
                          style: TextStyle(
                            color: colors.foreground,
                            fontSize: 15,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Piloter simplement',
                          style: TextStyle(color: colors.muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              _DrawerItem(
                icon: FLucideIcons.warehouse,
                label: 'Mes serres',
                selected: section == 0,
                onTap: () => onSelect(0),
              ),
              const SizedBox(height: 8),
              _DrawerItem(
                icon: Icons.photo_library_outlined,
                label: 'Galerie',
                selected: section == gallerySection,
                onTap: () => onSelect(gallerySection),
              ),
              const SizedBox(height: 8),
              _DrawerItem(
                icon: FLucideIcons.userRound,
                label: 'Compte',
                selected: section == accountSection,
                onTap: () => onSelect(accountSection),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Les réglages sont conservés sur cet appareil.',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected
                ? colors.accent.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? colors.accent : colors.muted,
              size: 21,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.foreground : colors.muted,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryPage extends StatefulWidget {
  const _GalleryPage({
    required this.api,
    required this.onOpenMenu,
  });

  final ApiClient api;
  final VoidCallback onOpenMenu;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  List<GalleryPhoto> photos = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final values = await widget.api.gallery();
      if (!mounted) return;
      setState(() {
        photos = values;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      final routeMissing =
          exception is ApiException && exception.statusCode == 404;
      setState(() {
        loading = false;
        error = routeMissing
            ? 'La galerie attend encore la route GET /api/gallery.'
            : exception.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        color: colors.accent,
        backgroundColor: colors.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    _MenuButton(onTap: widget.onOpenMenu),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Galerie',
                            style: TextStyle(
                              color: colors.foreground,
                              fontSize: 36,
                              height: 1,
                              letterSpacing: -1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Les photos capturées par vos serres',
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
              )
            else if (error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GalleryMessage(
                  icon: FLucideIcons.imageOff,
                  title: 'Galerie indisponible',
                  message: error!,
                  actionLabel: 'Réessayer',
                  onAction: _load,
                ),
              )
            else if (photos.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _GalleryMessage(
                  icon: Icons.photo_library_outlined,
                  title: 'Aucune photo',
                  message:
                      'Les prochaines captures de la serre apparaîtront ici.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 42),
                sliver: SliverGrid.builder(
                  itemCount: photos.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.76,
                  ),
                  itemBuilder: (context, index) => _GalleryPhotoCard(
                    api: widget.api,
                    photo: photos[index],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 20, 30, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, color: colors.accent, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: colors.foreground,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                style: appPrimaryButtonStyle(context, height: 48),
                onPressed: onAction,
                icon: const Icon(FLucideIcons.refreshCw, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GalleryPhotoCard extends StatelessWidget {
  const _GalleryPhotoCard({
    required this.api,
    required this.photo,
  });

  final ApiClient api;
  final GalleryPhoto photo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _GalleryPhotoViewer(api: api, photo: photo),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: 'gallery-photo-${photo.id}',
                child: _GalleryNetworkImage(
                  api: api,
                  url: photo.thumbnailUrl,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.greenhouseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _galleryDate(photo.capturedAt),
                    style: TextStyle(color: colors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryNetworkImage extends StatelessWidget {
  const _GalleryNetworkImage({
    required this.api,
    required this.url,
    this.fit = BoxFit.cover,
  });

  final ApiClient api;
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (url.trim().isEmpty) {
      return ColoredBox(
        color: colors.surfaceSoft,
        child: Center(
          child: Icon(
            FLucideIcons.imageOff,
            color: colors.muted,
            size: 30,
          ),
        ),
      );
    }
    return Image.network(
      api.resolveMediaUrl(url).toString(),
      headers: api.mediaHeaders,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : ColoredBox(
              color: colors.surfaceSoft,
              child: Center(
                child: CircularProgressIndicator(
                  color: colors.accent,
                  strokeWidth: 2,
                ),
              ),
            ),
      errorBuilder: (_, __, ___) => ColoredBox(
        color: colors.surfaceSoft,
        child: Center(
          child: Icon(
            FLucideIcons.imageOff,
            color: colors.muted,
            size: 30,
          ),
        ),
      ),
    );
  }
}

class _GalleryPhotoViewer extends StatelessWidget {
  const _GalleryPhotoViewer({
    required this.api,
    required this.photo,
  });

  final ApiClient api;
  final GalleryPhoto photo;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xff080b0a),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(photo.greenhouseName),
        ),
        body: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: 'gallery-photo-${photo.id}',
                    child: _GalleryNetworkImage(
                      api: api,
                      url: photo.imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                child: Row(
                  children: [
                    const Icon(
                      FLucideIcons.camera,
                      color: Color(0xff69e1c1),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        photo.caption?.trim().isNotEmpty == true
                            ? photo.caption!
                            : _galleryDate(photo.capturedAt),
                        style: const TextStyle(
                          color: Color(0xffd3dad9),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

String _galleryDate(DateTime? value) {
  if (value == null) return 'Date inconnue';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} · '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _ChallengesPage extends StatelessWidget {
  const _ChallengesPage();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 40),
        children: [
          Text(
            'Défis',
            style: TextStyle(
              color: colors.foreground,
              fontSize: 36,
              height: 1,
              letterSpacing: -1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'De petits objectifs pour une serre plus saine',
            style: TextStyle(color: colors.muted, fontSize: 14),
          ),
          const SizedBox(height: 28),
          const _ChallengeCard(
            icon: FLucideIcons.droplets,
            title: 'Maîtriser l’arrosage',
            description: 'Maintenir l’humidité du sol entre 45 et 65 %.',
            progress: 0.78,
            current: '11 jours',
            target: '14 jours',
            color: Color(0xff62dfe2),
          ),
          const SizedBox(height: 14),
          const _ChallengeCard(
            icon: FLucideIcons.leaf,
            title: 'Croissance régulière',
            description: 'Consulter les mesures chaque jour cette semaine.',
            progress: 0.57,
            current: '4 jours',
            target: '7 jours',
            color: Color(0xff68e27e),
          ),
          const SizedBox(height: 14),
          const _ChallengeCard(
            icon: FLucideIcons.zap,
            title: 'Énergie maîtrisée',
            description: 'Réduire l’éclairage automatique de 10 %.',
            progress: 0.35,
            current: '3 %',
            target: '10 %',
            color: Color(0xffffc66d),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.progress,
    required this.current,
    required this.target,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final double progress;
  final String current;
  final String target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.foreground,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            description,
            style: TextStyle(
              color: colors.muted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: color,
              backgroundColor: colors.surfaceSoft,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                current,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                target,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountPage extends StatelessWidget {
  const _AccountPage({
    required this.profile,
    required this.profileError,
    required this.onRetryProfile,
    required this.onLogout,
    required this.darkMode,
    required this.onThemeChanged,
    required this.onClearLocalData,
    required this.onOpenMenu,
  });

  final UserProfile? profile;
  final String? profileError;
  final VoidCallback onRetryProfile;
  final VoidCallback onLogout;
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onClearLocalData;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 40),
        children: [
          Row(
            children: [
              _MenuButton(onTap: onOpenMenu),
              const SizedBox(width: 14),
              Text(
                'Compte',
                style: TextStyle(
                  color: colors.foreground,
                  fontSize: 36,
                  height: 1,
                  letterSpacing: -1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xff1c3531),
                  child: Text(
                    profile?.initials.isNotEmpty == true
                        ? profile!.initials
                        : '••',
                    style: const TextStyle(
                      color: Color(0xff68e2bd),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ??
                            (profileError == null
                                ? 'Chargement du profil…'
                                : 'Profil indisponible'),
                        style: TextStyle(
                          color: colors.foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        profile?.email ??
                            profileError ??
                            'Connexion au compte en cours',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: profileError == null ? null : onRetryProfile,
                  tooltip: profileError == null ? null : 'Réessayer',
                  icon: Icon(
                    profileError == null
                        ? FLucideIcons.userRound
                        : FLucideIcons.refreshCw,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  darkMode ? FLucideIcons.moon : FLucideIcons.sun,
                  color: colors.foreground,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode sombre',
                        style: TextStyle(
                          color: colors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        darkMode ? 'Activé' : 'Mode clair activé',
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: darkMode,
                  activeThumbColor: colors.accent,
                  activeTrackColor: colors.accent.withValues(alpha: 0.34),
                  inactiveThumbColor: colors.muted,
                  inactiveTrackColor: colors.surfaceSoft,
                  trackOutlineColor:
                      const WidgetStatePropertyAll(Colors.transparent),
                  onChanged: onThemeChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _AccountItem(
            icon: FLucideIcons.database,
            title: 'Données locales',
            detail: 'Effacer les noms, pictogrammes et délais',
            onTap: onClearLocalData,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FButton(
              variant: FButtonVariant.outline,
              prefix: const Icon(FLucideIcons.logOut, size: 19),
              onPress: onLogout,
              child: const Text('Se déconnecter'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountItem extends StatelessWidget {
  const _AccountItem({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.muted, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              FLucideIcons.chevronRight,
              color: colors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onLogout,
    required this.onOpenMenu,
  });

  final VoidCallback onLogout;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _MenuButton(onTap: onOpenMenu),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mes serres',
                style: TextStyle(
                  color: colors.foreground,
                  fontSize: 36,
                  height: 1,
                  letterSpacing: -1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'Tous vos espaces en un coup d’œil',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 14,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onLongPress: onLogout,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    FLucideIcons.bell,
                    color: colors.foreground.withValues(alpha: 0.76),
                    size: 22,
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xff68e27e),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x8068e27e),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: Icon(
          FLucideIcons.menu,
          color: colors.foreground,
          size: 22,
        ),
      ),
    );
  }
}

class _GreenhouseCard extends StatelessWidget {
  const _GreenhouseCard({
    required this.greenhouse,
    required this.displayName,
    required this.plantEmoji,
    required this.reading,
    required this.loading,
    required this.imageAsset,
    required this.onTap,
  });

  final Greenhouse greenhouse;
  final String displayName;
  final String plantEmoji;
  final SensorReading? reading;
  final bool loading;
  final String imageAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1.32,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(imageAsset),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.46, 1],
                        colors: [
                          Color(0x3d000000),
                          Color(0x18000000),
                          Color(0xe6000000),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 16,
                    child: _GlassPill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: greenhouse.online
                                  ? const Color(0xff68e27e)
                                  : const Color(0xff8b9695),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            plantEmoji,
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: _GlassPill(
                      padding: const EdgeInsets.all(11),
                      child: const Icon(
                        FLucideIcons.ellipsis,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 17,
                    child: Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            icon: FLucideIcons.thermometer,
                            value: loading
                                ? '—'
                                : '${reading?.temperature?.round() ?? '—'}°',
                            label: 'Température',
                          ),
                        ),
                        Container(
                          height: 40,
                          width: 1,
                          color: const Color(0x33ffffff),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _Metric(
                            icon: FLucideIcons.droplets,
                            value: loading
                                ? '—'
                                : '${reading?.airHumidity?.round() ?? '—'}%',
                            label: 'Humidité',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xb0151a1a),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: const Color(0x29ffffff)),
        ),
        child: child,
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: const Color(0xff62dfe2), size: 27),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  height: 1,
                  letterSpacing: -0.8,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xffaeb6b5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      );
}
