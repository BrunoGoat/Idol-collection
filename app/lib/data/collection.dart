import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/idol.dart';
import '../models/layout.dart';
import '../services/image_tools.dart';
import 'github_client.dart';
import 'local_store.dart';
import 'settings.dart';

const kLayoutPath = 'collection/layout.json';

enum SyncStatus { idle, syncing, ok, offline, error, notConfigured }

/// El estado completo de la colección. La fuente de verdad es el repo; esto es
/// una copia local que se actualiza sola al abrir la app y sube lo que cambies.
class Collection extends ChangeNotifier {
  Collection._(this.settings, this.store, this._baseDir, this._httpFactory);

  final AppSettings settings;
  final Directory? _baseDir;
  final http.Client Function()? _httpFactory;
  LocalStore store;

  final Map<String, Idol> idols = {};
  BoardLayout layout = BoardLayout();

  /// Número de colección que se muestra en cada carta (#001…).
  final Map<String, int> numbers = {};

  /// Miniaturas generadas en el teléfono.
  final Map<String, File> thumbs = {};

  /// Ídolos que llegaron del repo desde la última vez: se revelan con animación.
  final List<String> arrivals = [];

  SyncStatus status = SyncStatus.idle;
  String? lastError;
  DateTime? lastSync;

  Future<void>? _syncing;
  Future<void>? _syncAgain;
  Timer? _pushTimer;
  bool _pushing = false;
  final Set<String> _touchedDuringPush = {};
  bool _thumbsRunning = false;

  /// [baseDir] y [httpFactory] existen para los tests.
  static Future<Collection> open(AppSettings settings, {Directory? baseDir, http.Client Function()? httpFactory}) async {
    final c = Collection._(settings, await _storeFor(settings, baseDir), baseDir, httpFactory);
    await c._reload();
    return c;
  }

  static Future<LocalStore> _storeFor(AppSettings s, Directory? baseDir) async {
    final base = baseDir ?? await getApplicationSupportDirectory();
    final key = s.repoKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final store = LocalStore(Directory(p.join(base.path, 'collections', key)));
    await store.open();
    return store;
  }

  /// Llamar después de cambiar el repo en ajustes.
  Future<void> repoChanged() async {
    store = await _storeFor(settings, _baseDir);
    idols.clear();
    thumbs.clear();
    await _reload();
    await sync();
  }

  List<Idol> get sortedIdols => idols.values.toList()
    ..sort((a, b) => (numbers[a.id] ?? 0).compareTo(numbers[b.id] ?? 0));

  Set<String> get categories => {
        for (final i in idols.values)
          if (i.category != null) i.category!,
      };

  int get pendingCount => store.pending.count;

  File imageFile(Idol idol) => store.file(idol.imagePath);

  // -------------------------------------------------------------------------
  // Sincronización
  // -------------------------------------------------------------------------

  /// Si ya hay una sincronización en curso, encola otra para después: así lo
  /// que cambiaste mientras tanto también se sube.
  Future<void> sync() {
    final running = _syncing;
    if (running != null) {
      return _syncAgain ??= running.then((_) {
        _syncAgain = null;
        return sync();
      });
    }
    return _syncing = _doSync().whenComplete(() => _syncing = null);
  }

  Future<void> _doSync() async {
    if (!settings.isConfigured) {
      status = SyncStatus.notConfigured;
      notifyListeners();
      return;
    }
    status = SyncStatus.syncing;
    notifyListeners();
    final client = GitHubClient(
      token: settings.token,
      owner: settings.owner,
      repo: settings.repo,
      branch: settings.branch,
      httpClient: _httpFactory?.call(),
    );
    try {
      await _push(client);
      await _pull(client);
      status = SyncStatus.ok;
      lastError = null;
      lastSync = DateTime.now();
    } on SocketException {
      status = SyncStatus.offline;
    } on http.ClientException {
      status = SyncStatus.offline;
    } on GitHubException catch (e) {
      status = SyncStatus.error;
      lastError = e.toString();
    } catch (e) {
      status = SyncStatus.error;
      lastError = e.toString();
    } finally {
      client.close();
    }
    await _reload(detectArrivals: status == SyncStatus.ok);
  }

  Future<void> _push(GitHubClient client) async {
    final pending = store.pending;
    if (pending.isEmpty) return;
    _pushing = true;
    _touchedDuringPush.clear();
    try {
      final files = <String, Uint8List?>{};
      final paths = {...pending.files};
      final layoutIds = {...pending.layoutIds};
      final theme = pending.theme;
      for (final path in paths) {
        final bytes = await store.readBytes(path);
        // Borrar algo que nunca llegó al repo no hace falta.
        if (bytes == null && store.shaOf(path) == null) continue;
        files[path] = bytes;
      }
      if (layoutIds.isNotEmpty || theme) {
        // Fusiona con la versión del repo: solo pisamos las cartas que tocamos.
        final remote = BoardLayout.fromJsonString(await client.readText(kLayoutPath));
        for (final id in layoutIds) {
          final local = layout.cards[id];
          if (local != null && idols.containsKey(id)) {
            remote.cards[id] = local.copy();
          } else {
            remote.cards.remove(id);
          }
        }
        if (theme) remote.theme = layout.theme;
        final bytes = Uint8List.fromList(utf8.encode(remote.toJsonString()));
        await store.file(kLayoutPath).parent.create(recursive: true);
        await store.file(kLayoutPath).writeAsBytes(bytes, flush: true);
        files[kLayoutPath] = bytes;
      }
      if (files.isNotEmpty) {
        await client.commit(_commitMessage(pending.messages), files);
        for (final path in files.keys) {
          await store.markPushed(path);
        }
      }
      paths.where((x) => !_touchedDuringPush.contains(x)).forEach(pending.files.remove);
      layoutIds.where((x) => !_touchedDuringPush.contains('layout:$x')).forEach(pending.layoutIds.remove);
      if (theme && !_touchedDuringPush.contains('theme')) pending.theme = false;
      if (pending.isEmpty) pending.messages.clear();
      await store.savePending();
      await store.saveIndex();
    } finally {
      _pushing = false;
    }
  }

  String _commitMessage(List<String> messages) {
    final unique = messages.toSet().toList();
    if (unique.isEmpty) return 'App: reacomodar el tablero';
    if (unique.length == 1) return 'App: ${unique.first}';
    return 'App: ${unique.length} cambios en la colección\n\n${unique.map((m) => '- $m').join('\n')}';
  }

  Future<void> _pull(GitHubClient client) async {
    final remote = await client.listFiles('collection/');
    final remotePaths = {for (final f in remote) f.path: f};
    final pending = store.pending;
    final layoutDirty = pending.layoutIds.isNotEmpty || pending.theme;

    final toDownload = <RemoteFile>[];
    for (final f in remote) {
      if (pending.files.contains(f.path)) continue;
      if (f.path == kLayoutPath && layoutDirty) continue;
      if (store.shaOf(f.path) == f.sha && await store.exists(f.path)) continue;
      toDownload.add(f);
    }
    // Descarga de a 4 en paralelo.
    for (var i = 0; i < toDownload.length; i += 4) {
      await Future.wait(toDownload.skip(i).take(4).map((f) async {
        final bytes = await client.downloadBlob(f.sha);
        await store.writeSynced(f.path, bytes, f.sha);
        FileImage(store.file(f.path)).evict();
      }));
    }
    for (final path in store.indexedPaths.toList()) {
      if (!remotePaths.containsKey(path) && !pending.files.contains(path)) {
        await store.deleteSynced(path);
      }
    }
    await store.removeEmptyDirs();
    await store.saveIndex();
  }

  /// Relee todo desde el espejo local.
  Future<void> _reload({bool detectArrivals = false}) async {
    final loaded = <String, Idol>{};
    for (final id in await store.idolIds()) {
      try {
        final md = await store.readText('collection/idols/$id/card.md');
        if (md != null) loaded[id] = Idol.fromMarkdown(id, md);
      } catch (e) {
        debugPrint('No se pudo leer $id: $e');
      }
    }
    idols
      ..clear()
      ..addAll(loaded);

    layout = BoardLayout.fromJsonString(await store.readText(kLayoutPath));
    layout.cards.removeWhere((id, _) => !idols.containsKey(id));
    // Cartas agregadas directo en el repo, sin posición: les buscamos lugar.
    var placedNew = false;
    for (final idol in idols.values.toList()..sort((a, b) => a.added.compareTo(b.added))) {
      if (!layout.cards.containsKey(idol.id)) {
        layout.cards[idol.id] = layout.findFreeSpot(seed: idol.id.hashCode);
        _markLayout(idol.id);
        placedNew = true;
      }
    }
    if (placedNew) {
      await _saveLayoutLocal();
      await store.savePending();
    }

    // Numeración: la explícita manda; el resto por fecha de alta.
    numbers.clear();
    final byDate = idols.values.toList()
      ..sort((a, b) {
        final c = a.added.compareTo(b.added);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final used = {for (final i in byDate) if (i.number != null) i.number!};
    var next = 1;
    for (final idol in byDate) {
      if (idol.number != null) {
        numbers[idol.id] = idol.number!;
      } else {
        while (used.contains(next)) {
          next++;
        }
        numbers[idol.id] = next;
        used.add(next);
      }
    }

    if (detectArrivals) {
      final all = idols.keys.toSet();
      if (settings.hasSeenAnything) {
        final seen = settings.seenIds;
        final fresh = all.difference(seen).where((id) => !arrivals.contains(id)).toList()
          ..sort((a, b) => idols[a]!.added.compareTo(idols[b]!.added));
        arrivals.addAll(fresh);
      }
      await settings.setSeenIds(all);
    }

    thumbs.removeWhere((id, _) => !idols.containsKey(id));
    notifyListeners();
    unawaited(_ensureThumbs());
  }

  Future<void> _ensureThumbs() async {
    if (_thumbsRunning) return;
    _thumbsRunning = true;
    try {
      var changed = 0;
      for (final idol in idols.values.toList()) {
        final bytes = await store.readBytes(idol.imagePath);
        if (bytes == null) continue;
        final sha = store.shaOf(idol.imagePath) ?? gitBlobSha(bytes);
        final file = store.thumbFile(idol.id, sha);
        if (!await file.exists()) {
          try {
            await file.writeAsBytes(await makeThumbnail(bytes), flush: true);
            await store.pruneThumbs(idol.id, file);
          } catch (e) {
            debugPrint('Miniatura fallida para ${idol.id}: $e');
            continue;
          }
        }
        if (thumbs[idol.id]?.path != file.path) {
          thumbs[idol.id] = file;
          if (++changed % 6 == 0) notifyListeners();
        }
      }
      if (changed > 0) notifyListeners();
    } finally {
      _thumbsRunning = false;
    }
  }

  // -------------------------------------------------------------------------
  // Cambios desde la app
  // -------------------------------------------------------------------------

  void _touch(String key) {
    if (_pushing) _touchedDuringPush.add(key);
  }

  void _markLayout(String id) {
    store.pending.layoutIds.add(id);
    _touch('layout:$id');
  }

  Future<void> _writeLocal(String path, Uint8List bytes) async {
    await store.writeLocal(path, bytes);
    _touch(path);
  }

  Future<void> _deleteLocal(String path) async {
    await store.deleteLocal(path);
    _touch(path);
  }

  Future<void> _saveLayoutLocal() async {
    final f = store.file(kLayoutPath);
    await f.parent.create(recursive: true);
    await f.writeAsString(layout.toJsonString(), flush: true);
  }

  void _schedulePush([Duration delay = const Duration(seconds: 2)]) {
    _pushTimer?.cancel();
    _pushTimer = Timer(delay, sync);
  }

  int get _maxNumber => numbers.values.fold(0, math.max);

  /// Agrega un ídolo nuevo. [rawImage] es la foto tal cual la eligió el usuario.
  Future<Idol> addIdol(Idol draft, Uint8List rawImage, {Offset? near}) async {
    var id = slugify(draft.name);
    if (idols.containsKey(id)) {
      var n = 2;
      while (idols.containsKey('$id-$n')) {
        n++;
      }
      id = '$id-$n';
    }
    final idol = Idol.fromMarkdown(id, draft.toMarkdown())
      ..image = 'image.jpg'
      ..number = draft.number ?? _maxNumber + 1;
    final bytes = await prepareForRepo(rawImage);
    await _writeLocal(idol.imagePath, bytes);
    await _writeLocal(idol.mdPath, Uint8List.fromList(utf8.encode(idol.toMarkdown())));
    layout.cards[id] = layout.findFreeSpot(nearX: near?.dx, nearY: near?.dy, seed: id.hashCode);
    _markLayout(id);
    await _saveLayoutLocal();
    store.pending.messages.add('agregar a ${idol.name}');
    await store.savePending();
    await settings.setSeenIds({...settings.seenIds, id});
    await _reload();
    _schedulePush(Duration.zero);
    return idols[id] ?? idol;
  }

  Future<void> updateIdol(Idol idol, {Uint8List? newImage}) async {
    if (newImage != null) {
      final bytes = await prepareForRepo(newImage);
      if (idol.image != 'image.jpg') await _deleteLocal(idol.imagePath);
      idol.image = 'image.jpg';
      await _writeLocal(idol.imagePath, bytes);
      FileImage(imageFile(idol)).evict();
    }
    await _writeLocal(idol.mdPath, Uint8List.fromList(utf8.encode(idol.toMarkdown())));
    store.pending.messages.add('editar a ${idol.name}');
    await store.savePending();
    await _reload();
    _schedulePush(Duration.zero);
  }

  Future<void> deleteIdol(String id) async {
    final idol = idols[id];
    if (idol == null) return;
    final folder = '${idol.folder}/';
    final paths = {
      idol.mdPath,
      idol.imagePath,
      ...store.indexedPaths.where((x) => x.startsWith(folder)),
    };
    for (final path in paths) {
      await _deleteLocal(path);
    }
    layout.cards.remove(id);
    _markLayout(id);
    await _saveLayoutLocal();
    store.pending.messages.add('quitar a ${idol.name}');
    await store.savePending();
    await _reload();
    _schedulePush(Duration.zero);
  }

  /// Guarda la posición de una carta (después de moverla o redimensionarla).
  Future<void> commitPlacement(String id) async {
    _markLayout(id);
    await _saveLayoutLocal();
    await store.savePending();
    notifyListeners();
    _schedulePush(const Duration(seconds: 4));
  }

  Future<void> bringToFront(String id) async {
    final pl = layout.cards[id];
    if (pl == null) return;
    pl.z = layout.maxZ + 1;
    await commitPlacement(id);
  }

  Future<void> setTheme(String themeId) async {
    layout.theme = themeId;
    store.pending.theme = true;
    _touch('theme');
    await _saveLayoutLocal();
    await store.savePending();
    notifyListeners();
    _schedulePush();
  }

  String? takeArrival() => arrivals.isEmpty ? null : arrivals.removeAt(0);
}
