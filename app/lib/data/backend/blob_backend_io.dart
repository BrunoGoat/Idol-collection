import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'blob_backend.dart';

BlobBackend create(String name, {String? basePath}) => _FileBackend(name, basePath);

/// Cada clave es un archivo dentro de la carpeta de la app.
class _FileBackend extends BlobBackend {
  _FileBackend(this.name, this.basePath);

  final String name;
  final String? basePath;
  late Directory _root;

  @override
  Future<void> open() async {
    final base = basePath ?? (await getApplicationSupportDirectory()).path;
    _root = Directory(p.join(base, 'collections', name));
    await _root.create(recursive: true);
  }

  File _file(String key) => File(p.join(_root.path, key));

  @override
  Future<Uint8List?> read(String key) async {
    try {
      return await _file(key).readAsBytes();
    } on FileSystemException {
      return null; // No existe, o se borró mientras tanto.
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final f = _file(key);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _file(key).delete();
    } on FileSystemException {
      // Ya no estaba.
    }
  }

  @override
  Future<bool> exists(String key) => _file(key).exists();

  @override
  Future<List<String>> keys(String prefix) async {
    final dir = Directory(p.join(_root.path, prefix));
    final start = prefix.endsWith('/') ? dir : dir.parent;
    if (!await start.exists()) return [];
    final out = <String>[];
    await for (final e in start.list(recursive: true)) {
      if (e is! File) continue;
      final key = p.relative(e.path, from: _root.path).replaceAll(r'\', '/');
      if (key.startsWith(prefix)) out.add(key);
    }
    return out;
  }

  @override
  Future<void> clear() async {
    if (await _root.exists()) await _root.delete(recursive: true);
    await _root.create(recursive: true);
  }

  @override
  Future<void> tidy() async {
    final idols = Directory(p.join(_root.path, 'mirror', 'collection', 'idols'));
    if (!await idols.exists()) return;
    await for (final e in idols.list()) {
      if (e is Directory && await e.list().isEmpty) await e.delete();
    }
  }
}
