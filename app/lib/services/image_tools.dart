import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Achica una imagen para el repo: lado mayor ≤ [maxSide], JPEG de buena calidad.
/// Corre en otro hilo para no trabar la interfaz.
Future<Uint8List> prepareForRepo(Uint8List bytes, {int maxSide = 1600}) async {
  // En la web no hay hilos: recodificar una foto grande trabaría la página.
  // Ahí el selector de imágenes ya la entrega achicada en JPEG (ver editor).
  final isJpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  if (kIsWeb && isJpeg) return bytes;
  return compute(_resize, _ResizeJob(bytes, maxSide, 88));
}

/// Miniatura para cuando el tablero está muy alejado.
Future<Uint8List> makeThumbnail(Uint8List bytes) => compute(_resize, _ResizeJob(bytes, 360, 80));

class _ResizeJob {
  _ResizeJob(this.bytes, this.maxSide, this.quality);
  final Uint8List bytes;
  final int maxSide;
  final int quality;
}

Uint8List _resize(_ResizeJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw const FormatException('No se pudo leer la imagen');
  final image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  final out = longest <= job.maxSide
      ? image
      : img.copyResize(
          image,
          width: image.width >= image.height ? job.maxSide : null,
          height: image.height > image.width ? job.maxSide : null,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodeJpg(out, quality: job.quality));
}
