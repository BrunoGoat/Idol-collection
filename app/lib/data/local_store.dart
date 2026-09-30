import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// SHA que git le asigna a un archivo: `sha1("blob <tamaño>\0<contenido>")`.
String gitBlobSha(Uint8List bytes) {
  final header = utf8.encode('blob ${bytes.length}\u0000');
  return sha1.convert([...header, ...bytes]).toString();
}

/// Cambios hechos en el teléfono que todavía no llegaron al repo.
class PendingChanges {
  PendingChanges({Set<String>? files, Set<String>? layoutIds, this.theme = false, List<String>? messages})
      : files = files ?? {},
        layoutIds = layoutIds ?? {},
        messages = messages ?? [];

  /// Rutas del repo modificadas. Si el archivo ya no existe en el espejo local, es un borrado.
  final Set<String> files;

  /// Cartas cuya posición cambió (o que se borraron) en layout.json.
  final Set<String> layoutIds;
  bool theme;
  final List<String> messages;

  bool get isEmpty => files.isEmpty && layoutIds.isEmpty && !theme;
  int get count => files.length + layoutIds.length + (theme ? 1 : 0);

  factory PendingChanges.fromJson(Map<String, dynamic> j) => PendingChanges(
        files: {...(j['files'] as List? ?? const []).cast<String>()},
        layoutIds: {...(j['layoutIds'] as List? ?? const []).cast<String>()},
        theme: j['theme'] == true,
        messages: [...(j['messages'] as List? ?? const []).cast<String>()],
      );

  Map<String, dynamic> toJson() => {
        'files': files.toList(),
        'layoutIds': layoutIds.toList(),
        'theme': theme,
        'messages': messages,
      };

  void clear() {
    files.clear();
    layoutIds.clear();
    theme = false;
    messages.clear();
  }
}

/// Copia local de la carpeta `collection/` del repo, para abrir al instante y
/// funcionar sin internet.
class LocalStore {
  LocalStore(this.root);

  final Directory root;
  late Map<String, String> _index; // ruta del repo → sha
  late PendingChanges pending;

  Directory get mirror => Directory(p.join(root.path, 'mirror'));
  Directory get thumbs => Directory(p.join(root.path, 'thumbs'));
  File get _indexFile => File(p.join(root.path, 'index.json'));
  File get _pendingFile => File(p.join(root.path, 'pending.json'));

  Future<void> open() async {
    await mirror.create(recursive: true);
    await thumbs.create(recursive: true);
    _index = await _readJson(_indexFile).then((j) => j.cast<String, String>());
    pending = PendingChanges.fromJson(await _readJson(_pendingFile));
  }

  Future<Map<String, dynamic>> _readJson(File f) async {
    if (!await f.exists()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveIndex() => _indexFile.writeAsString(jsonEncode(_index));
  Future<void> savePending() => _pendingFile.writeAsString(jsonEncode(pending.toJson()));

  File file(String repoPath) => File(p.join(mirror.path, repoPath));

  String? shaOf(String repoPath) => _index[repoPath];
  Iterable<String> get indexedPaths => _index.keys;

  Future<bool> exists(String repoPath) => file(repoPath).exists();

  Future<String?> readText(String repoPath) async {
    final f = file(repoPath);
    return await f.exists() ? f.readAsString() : null;
  }

  Future<Uint8List?> readBytes(String repoPath) async {
    final f = file(repoPath);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Escribe un archivo que vino del repo (queda sincronizado).
  Future<void> writeSynced(String repoPath, Uint8List bytes, String sha) async {
    final f = file(repoPath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    _index[repoPath] = sha;
  }

  /// Escribe un cambio local, pendiente de subir.
  Future<void> writeLocal(String repoPath, Uint8List bytes) async {
    final f = file(repoPath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    pending.files.add(repoPath);
  }

  Future<void> deleteLocal(String repoPath) async {
    final f = file(repoPath);
    if (await f.exists()) await f.delete();
    pending.files.add(repoPath);
  }

  /// Borra un archivo que desapareció del repo.
  Future<void> deleteSynced(String repoPath) async {
    final f = file(repoPath);
    if (await f.exists()) await f.delete();
    _index.remove(repoPath);
  }

  /// Marca como sincronizado un archivo que acabamos de subir.
  Future<void> markPushed(String repoPath) async {
    final bytes = await readBytes(repoPath);
    if (bytes == null) {
      _index.remove(repoPath);
    } else {
      _index[repoPath] = gitBlobSha(bytes);
    }
  }

  /// Carpetas de ídolos presentes en el espejo.
  Future<List<String>> idolIds() async {
    final dir = Directory(p.join(mirror.path, 'collection', 'idols'));
    if (!await dir.exists()) return [];
    final ids = <String>[];
    await for (final e in dir.list()) {
      if (e is Directory && await File(p.join(e.path, 'card.md')).exists()) {
        ids.add(p.basename(e.path));
      }
    }
    return ids;
  }

  Future<void> removeEmptyDirs() async {
    final dir = Directory(p.join(mirror.path, 'collection', 'idols'));
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      if (e is Directory && await e.list().isEmpty) await e.delete();
    }
  }

  File thumbFile(String id, String imageSha) => File(p.join(thumbs.path, '$id-${imageSha.substring(0, 10)}.jpg'));

  /// Borra miniaturas viejas de una carta.
  Future<void> pruneThumbs(String id, File keep) async {
    await for (final e in thumbs.list()) {
      final name = p.basename(e.path);
      if (name.startsWith('$id-') && e.path != keep.path) await e.delete();
    }
  }

  /// Borra todo (al cambiar de repo).
  Future<void> wipe() async {
    if (await root.exists()) await root.delete(recursive: true);
    await open();
  }
}
