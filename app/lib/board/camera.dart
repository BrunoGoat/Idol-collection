import 'dart:math' as math;
import 'dart:ui';

import '../widgets/backgrounds.dart';

const double kMinZoom = 0.03;
const double kMaxZoom = 4.0;

/// Tamaño del lienzo interno. El origen del mundo (0,0) está en su centro.
const double kWorldSize = 100000;
const double kWorldHalf = kWorldSize / 2;

Offset worldToScreen(Offset world, CameraView cam, Size screen) =>
    (world - cam.center) * cam.zoom + screen.center(Offset.zero);

Offset screenToWorld(Offset point, CameraView cam, Size screen) =>
    (point - screen.center(Offset.zero)) / cam.zoom + cam.center;

Rect visibleWorld(CameraView cam, Size screen) =>
    Rect.fromCenter(center: cam.center, width: screen.width / cam.zoom, height: screen.height / cam.zoom);

/// Interpolación tipo "vuelo": se aleja un poco a mitad de camino si el
/// destino está lejos, como una cámara que toma altura.
CameraView flyLerp(CameraView a, CameraView b, double t, Size screen) {
  final center = Offset.lerp(a.center, b.center, t)!;
  final logZ = lerpDouble(math.log(a.zoom), math.log(b.zoom), t)!;
  final distance = (b.center - a.center).distance;
  final span = screen.shortestSide / math.min(a.zoom, b.zoom);
  final dip = (distance / span).clamp(0.0, 1.2) * 0.55;
  final zoom = math.exp(logZ) * (1 - dip * math.sin(math.pi * t));
  return CameraView(center, zoom.clamp(kMinZoom, kMaxZoom));
}
