import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'backend/blob_backend.dart';

/// Imagen guardada en el almacenamiento local (archivos o IndexedDB).
///
/// La identidad en el caché es clave + versión: cuando cambia la foto de una
/// carta cambia la versión, así que nunca se muestra la copia vieja.
@immutable
class StoreImage extends ImageProvider<StoreImage> {
  const StoreImage(this.backend, this.key, this.version);

  final BlobBackend backend;
  final String key;
  final String version;

  @override
  Future<StoreImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(StoreImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0, debugLabel: key.key);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await backend.read(key);
    if (bytes == null || bytes.isEmpty) {
      // Que el caché no se quede con el error: la imagen puede llegar después.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      throw StateError('Todavía no está la imagen $key');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is StoreImage && other.key == key && other.version == version;

  @override
  int get hashCode => Object.hash(key, version);

  @override
  String toString() => 'StoreImage($key@$version)';
}
