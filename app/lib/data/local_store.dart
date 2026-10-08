import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'backend/blob_backend.dart';

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
/// funcionar sin internet. Funciona igual en Android (archivos) y en la web
/// (IndexedDB) gracias a [BlobBackend].
class LocalStore {
  LocalStore(this.backend);

  final BlobBackend backend;
  late Map<String, String> _index; // ruta del repo → sha
  late PendingChanges pending;

  /// Versión de los archivos cambiados en esta sesión que todavía no tienen sha
  /// (para que las imágenes nuevas no usen la copia vieja del caché).
  final Map<String, String> _localStamp = {};

  static const _mirror = 'mirror/';
  static const _thumbs = 'thumbs/';

  Future<void> open() async {
    await backend.open();
    _index = (await _readJson('index.json')).cast<String, String>();
    pending = PendingChanges.fromJson(await _readJson('pending.json'));
  }

  Future<Map<String, dynamic>> _readJson(String key) async {
    final bytes = await backend.read(key);
    if (bytes == null) return {};
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeJson(String key, Object value) =>
      backend.write(key, Uint8List.fromList(utf8.encode(jsonEncode(value))));

  Future<void> saveIndex() => _writeJson('index.json', _index);
  Future<void> savePending() => _writeJson('pending.json', pending.toJson());

  /// Clave del almacenamiento para una ruta del repo.
  String keyOf(String repoPath) => '$_mirror$repoPath';

  String? shaOf(String repoPath) => _index[repoPath];
  Iterable<String> get indexedPaths => _index.keys;

  /// Identifica el contenido actual de un archivo (para el caché de imágenes).
  String versionOf(String repoPath) => _localStamp[repoPath] ?? _index[repoPath] ?? '0';

  Future<bool> exists(String repoPath) => backend.exists(keyOf(repoPath));

  Future<String?> readText(String repoPath) async {
    final bytes = await readBytes(repoPath);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<Uint8List?> readBytes(String repoPath) => backend.read(keyOf(repoPath));

  /// Escribe sin marcarlo como cambio pendiente (lo usa layout.json, que se
  /// sube fusionado por carta).
  Future<void> writeRaw(String repoPath, Uint8List bytes) => backend.write(keyOf(repoPath), bytes);

  /// Escribe un archivo que vino del repo (queda sincronizado).
  Future<void> writeSynced(String repoPath, Uint8List bytes, String sha) async {
    await backend.write(keyOf(repoPath), bytes);
    _index[repoPath] = sha;
    _localStamp.remove(repoPath);
  }

  /// Escribe un cambio local, pendiente de subir.
  Future<void> writeLocal(String repoPath, Uint8List bytes) async {
    await backend.write(keyOf(repoPath), bytes);
    pending.files.add(repoPath);
    _localStamp[repoPath] = 'local-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> deleteLocal(String repoPath) async {
    await backend.delete(keyOf(repoPath));
    pending.files.add(repoPath);
  }

  /// Borra un archivo que desapareció del repo.
  Future<void> deleteSynced(String repoPath) async {
    await backend.delete(keyOf(repoPath));
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

  /// Carpetas de ídolos presentes en el espejo (las que tienen card.md).
  Future<List<String>> idolIds() async {
    const prefix = '${_mirror}collection/idols/';
    return [
      for (final k in await backend.keys(prefix))
        if (k.endsWith('/card.md') && k.substring(prefix.length).split('/').length == 2)
          k.substring(prefix.length).split('/').first,
    ];
  }

  Future<void> removeEmptyDirs() => backend.tidy();

  String thumbKey(String id, String imageSha) => '$_thumbs$id-${imageSha.substring(0, 10)}.jpg';

  Future<bool> hasThumb(String key) => backend.exists(key);
  Future<void> writeThumb(String key, Uint8List bytes) => backend.write(key, bytes);

  /// Borra miniaturas viejas de una carta.
  Future<void> pruneThumbs(String id, String keep) async {
    for (final k in await backend.keys('$_thumbs$id-')) {
      if (k != keep) await backend.delete(k);
    }
  }

  /// Borra todo (al cambiar de repo).
  Future<void> wipe() async {
    await backend.clear();
    _index = {};
    pending = PendingChanges();
  }
}
