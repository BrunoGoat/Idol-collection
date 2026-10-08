import 'dart:typed_data';

import 'blob_backend_io.dart' if (dart.library.js_interop) 'blob_backend_web.dart' as impl;

/// Almacenamiento clave → bytes donde vive la copia local de la colección.
/// En Android son archivos; en la web, IndexedDB (la base de datos del navegador).
abstract class BlobBackend {
  Future<void> open();
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> delete(String key);
  Future<bool> exists(String key);

  /// Claves que empiezan con [prefix].
  Future<List<String>> keys(String prefix);

  /// Borra todo.
  Future<void> clear();

  /// Ordenar después de borrar (carpetas vacías, etc.).
  Future<void> tidy() async {}
}

/// Crea el almacenamiento para un repo. [basePath] solo se usa en los tests.
BlobBackend createBackend(String name, {String? basePath}) => impl.create(name, basePath: basePath);
