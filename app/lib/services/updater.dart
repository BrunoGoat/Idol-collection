import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/github_client.dart';
import '../data/settings.dart';
import '../models/catalog.dart';

/// Una versión más nueva publicada en los Releases del repo.
class UpdateInfo {
  UpdateInfo({required this.build, required this.tag, required this.notes, required this.assetId});
  final int build;
  final String tag;
  final String notes;
  final int assetId;

  String get version => tag.replaceFirst('app-v', '');
}

/// Busca e instala versiones nuevas de la app desde los Releases del repo.
class Updater {
  Updater._();

  /// Número de compilación instalado (el de GitHub Actions).
  static Future<({int build, String version})> current() async {
    final info = await PackageInfo.fromPlatform();
    return (build: int.tryParse(info.buildNumber) ?? 0, version: info.version);
  }

  /// Devuelve la versión nueva, o null si ya estás al día.
  static Future<UpdateInfo?> check(AppSettings settings) async {
    if (!settings.isConfigured) return null;
    final client = _client(settings);
    try {
      final release = await client.latestRelease();
      if (release == null || release.apkAssetId == null) return null;
      final build = int.tryParse(RegExp(r'(\d+)$').firstMatch(release.tag)?.group(1) ?? '') ?? 0;
      final installed = (await current()).build;
      if (build <= installed) return null;
      return UpdateInfo(build: build, tag: release.tag, notes: release.notes, assetId: release.apkAssetId!);
    } finally {
      client.close();
    }
  }

  static GitHubClient _client(AppSettings s) =>
      GitHubClient(token: s.token, owner: s.owner, repo: s.repo, branch: s.branch);

  /// Descarga el APK y abre el instalador de Android (que actualiza encima).
  static Future<Stream<OtaEvent>> install(AppSettings settings, UpdateInfo update) async {
    final client = _client(settings);
    try {
      final url = await client.assetDownloadUrl(update.assetId);
      return OtaUpdate().execute(url, destinationFilename: 'salon-de-idolos.apk');
    } finally {
      client.close();
    }
  }
}

/// Diálogo "hay una versión nueva" con barra de progreso.
Future<void> showUpdateDialog(BuildContext context, AppSettings settings, UpdateInfo update) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(settings: settings, update: update),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.settings, required this.update});
  final AppSettings settings;
  final UpdateInfo update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  StreamSubscription<OtaEvent>? _sub;
  bool _working = false;
  double? _progress;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _working = true;
      _failed = false;
      _message = 'Preparando la descarga…';
    });
    try {
      final stream = await Updater.install(widget.settings, widget.update);
      _sub = stream.listen((e) {
        if (!mounted) return;
        setState(() {
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              _progress = (double.tryParse(e.value ?? '') ?? 0) / 100;
              _message = 'Descargando… ${e.value ?? 0}%';
            case OtaStatus.INSTALLING:
              _progress = 1;
              _message = 'Confirmá "Actualizar" en la ventana de Android.';
              _working = false;
            case OtaStatus.INSTALLATION_DONE:
              _message = '¡Listo!';
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              _fail('Android necesita permiso para instalar apps desde Salón de Ídolos. Activalo y volvé a intentar.');
            case OtaStatus.INSTALLATION_ERROR:
              _fail('Android no pudo actualizar. Si es la primera vez con la clave fija, desinstalá la app una única vez '
                  'e instalá esta versión desde Releases; de ahí en más se actualiza sola.');
            default:
              _fail('No se pudo actualizar (${e.status.name}${e.value == null ? '' : ': ${e.value}'}).');
          }
        });
      }, onError: (Object e) {
        if (mounted) setState(() => _fail('No se pudo actualizar: $e'));
      });
    } catch (e) {
      if (mounted) setState(() => _fail('No se pudo actualizar: $e'));
    }
  }

  void _fail(String msg) {
    _failed = true;
    _working = false;
    _message = msg;
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.update.notes.trim();
    return AlertDialog(
      title: Text('✨ Versión ${widget.update.version}', style: const TextStyle(fontFamily: kTitleFont)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hay una versión nueva del Salón de Ídolos. Se instala encima: no perdés nada.'),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(notes, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ],
          if (_message != null) ...[
            const SizedBox(height: 14),
            if (_working || _progress != null) LinearProgressIndicator(value: _failed ? 0 : _progress),
            const SizedBox(height: 8),
            Text(_message!, style: TextStyle(color: _failed ? Colors.redAccent : null)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: Text(_message == null ? 'Después' : 'Cerrar'),
        ),
        if (!_working && (_message == null || _failed))
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.system_update),
            label: Text(_failed ? 'Reintentar' : 'Actualizar'),
          ),
      ],
    );
  }
}
