import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/collection.dart';
import '../data/github_client.dart';
import '../models/catalog.dart';
import '../widgets/backgrounds.dart';
import 'catalog_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final settings = AppScope.of(context).settings;
  late final _owner = TextEditingController(text: settings.owner);
  late final _repo = TextEditingController(text: settings.repo);
  late final _branch = TextEditingController(text: settings.branch);
  late final _token = TextEditingController(text: settings.token);
  bool _showToken = false;
  bool _testing = false;
  String? _testResult;

  @override
  void dispose() {
    for (final c in [_owner, _repo, _branch, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = GitHubClient(token: _token.text.trim(), owner: _owner.text.trim(), repo: _repo.text.trim(), branch: _branch.text.trim());
    try {
      final files = await client.listFiles('collection/');
      final cards = files.where((f) => f.path.endsWith('/card.md')).length;
      _testResult = '✅ Conectado. Hay $cards ídolos en el repo.';
    } catch (e) {
      _testResult = '❌ $e';
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final collection = AppScope.of(context).collection;
    final repoChanged = _owner.text.trim() != settings.owner || _repo.text.trim() != settings.repo || _branch.text.trim() != settings.branch;
    await settings.saveRepo(owner: _owner.text, repo: _repo.text, branch: _branch.text, token: _token.text);
    if (repoChanged) {
      await collection.repoChanged();
    } else {
      await collection.sync();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(collection.status == SyncStatus.ok ? 'Guardado y sincronizado ✨' : 'Guardado. Estado: ${collection.lastError ?? collection.status.name}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final collection = AppScope.of(context).collection;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListenableBuilder(
        listenable: Listenable.merge([collection, settings]),
        builder: (context, _) {
          final theme = themeById(collection.layout.theme);
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const _Header('Tablero'),
              ListTile(
                leading: const Icon(Icons.wallpaper),
                title: const Text('Fondo del tablero'),
                subtitle: Text(theme.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen(initialTab: 0))),
              ),
              ListTile(
                leading: const Icon(Icons.crop_portrait),
                title: Text('Ver los ${kFrames.length} marcos'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen(initialTab: 1))),
              ),
              ListTile(
                leading: const Icon(Icons.font_download),
                title: Text('Ver las ${kFonts.length} fuentes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen(initialTab: 2))),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.hub),
                title: const Text('Constelaciones'),
                subtitle: const Text('Unir con luz a los ídolos de la misma categoría'),
                value: settings.constellations,
                onChanged: (v) => settings.setFlag('constellations', v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Ídolo del día'),
                subtitle: const Text('Al abrir la app, la cámara te lleva a uno'),
                value: settings.idolOfTheDay,
                onChanged: (v) => settings.setFlag('idolOfTheDay', v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.screen_rotation),
                title: const Text('Holograma por inclinación'),
                subtitle: const Text('Las cartas brillan al mover el teléfono'),
                value: settings.tiltHolo,
                onChanged: (v) => settings.setFlag('tiltHolo', v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up),
                title: const Text('Sonidos'),
                value: settings.sound,
                onChanged: (v) => settings.setFlag('sound', v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibración'),
                value: settings.haptics,
                onChanged: (v) => settings.setFlag('haptics', v),
              ),
              const _Header('Repositorio de GitHub'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Tu colección vive en la carpeta collection/ del repo. La app la baja al abrirse y sube lo que agregues o muevas.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
              _field(_owner, 'Dueño (usuario u organización)'),
              _field(_repo, 'Repositorio'),
              _field(_branch, 'Rama'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: TextField(
                  controller: _token,
                  obscureText: !_showToken,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Token de acceso (fine-grained)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _TokenHelp(),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _test,
                        icon: _testing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering),
                        label: const Text('Probar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Guardar')),
                    ),
                  ],
                ),
              ),
              if (_testResult != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_testResult!)),
              const _Header('Estado'),
              ListTile(
                leading: const Icon(Icons.sync),
                title: Text(switch (collection.status) {
                  SyncStatus.ok => 'Al día con el repo',
                  SyncStatus.syncing => 'Sincronizando…',
                  SyncStatus.offline => 'Sin conexión',
                  SyncStatus.error => 'Error: ${collection.lastError}',
                  SyncStatus.notConfigured => 'Sin configurar',
                  SyncStatus.idle => 'Esperando',
                }),
                subtitle: Text(
                  '${collection.pendingCount} cambios pendientes de subir'
                  '${collection.lastSync == null ? '' : ' · última sync ${TimeOfDay.fromDateTime(collection.lastSync!).format(context)}'}',
                ),
                trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: collection.sync),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: TextField(
          controller: c,
          autocorrect: false,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(text.toUpperCase(), style: const TextStyle(fontFamily: kTitleFont, letterSpacing: 2, color: Colors.amber)),
      );
}

class _TokenHelp extends StatelessWidget {
  const _TokenHelp();

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('¿Cómo creo el token?', style: TextStyle(fontSize: 14)),
        children: const [
          Text(
            '1. En GitHub: Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token.\n'
            '2. Repository access: "Only select repositories" → elegí Idol-collection.\n'
            '3. Permissions → Repository permissions → Contents: "Read and write".\n'
            '4. Generalo, copialo y pegalo acá. Se guarda cifrado en el teléfono.',
            style: TextStyle(height: 1.4),
          ),
          SizedBox(height: 8),
        ],
      );
}
