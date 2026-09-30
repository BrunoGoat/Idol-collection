import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/catalog.dart';
import '../models/idol.dart';
import '../models/layout.dart';
import '../widgets/backgrounds.dart';
import 'camera.dart';

Color categoryColor(String category) =>
    HSVColor.fromAHSV(1, (category.hashCode % 360).abs().toDouble(), 0.55, 1).toColor();

/// Constelaciones: une las cartas de la misma categoría con líneas de luz y,
/// de lejos, muestra el nombre de la zona.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.idols,
    required this.layout,
    required this.camera,
    required this.time,
  })  : _edges = _computeEdges(idols, layout),
        super(repaint: Listenable.merge([camera, time]));

  final Map<String, Idol> idols;
  final BoardLayout layout;
  final ValueNotifier<CameraView> camera;
  final ValueNotifier<double> time;
  final List<(String, String, String)> _edges;

  /// Árbol de expansión mínima por categoría (Prim): pocas líneas, sin cruces feos.
  static List<(String, String, String)> _computeEdges(Map<String, Idol> idols, BoardLayout layout) {
    final byCat = <String, List<String>>{};
    for (final i in idols.values) {
      if (i.category != null && layout.cards.containsKey(i.id)) {
        byCat.putIfAbsent(i.category!, () => []).add(i.id);
      }
    }
    final edges = <(String, String, String)>[];
    for (final entry in byCat.entries) {
      final ids = entry.value;
      if (ids.length < 2) continue;
      final inTree = {ids.first};
      while (inTree.length < ids.length) {
        String? bestA, bestB;
        var best = double.infinity;
        for (final a in inTree) {
          final pa = layout.cards[a]!;
          for (final b in ids) {
            if (inTree.contains(b)) continue;
            final pb = layout.cards[b]!;
            final d = math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2);
            if (d < best) {
              best = d.toDouble();
              bestA = a;
              bestB = b;
            }
          }
        }
        inTree.add(bestB!);
        edges.add((bestA!, bestB, entry.key));
      }
    }
    return edges;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cam = camera.value;
    final t = time.value;
    final pulse = 0.5 + 0.5 * math.sin(t * 1.3);
    for (final (a, b, cat) in _edges) {
      final pa = layout.cards[a], pb = layout.cards[b];
      if (pa == null || pb == null) continue;
      final sa = worldToScreen(Offset(pa.x, pa.y), cam, size);
      final sb = worldToScreen(Offset(pb.x, pb.y), cam, size);
      final color = categoryColor(cat);
      canvas.drawLine(
        sa,
        sb,
        Paint()
          ..color = color.withValues(alpha: 0.10 + 0.08 * pulse)
          ..strokeWidth = 3 + 4 * cam.zoom
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawLine(
        sa,
        sb,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      // Una chispa que viaja por la línea.
      final k = (t * 0.25 + a.hashCode % 100 / 100) % 1.0;
      canvas.drawCircle(Offset.lerp(sa, sb, k)!, 2.2, Paint()..color = color.withValues(alpha: 0.9));
    }

    // Nombres de zona cuando estás lejos.
    final labelAlpha = 1 - ((cam.zoom - 0.1) / 0.12).clamp(0.0, 1.0);
    if (labelAlpha <= 0.01) return;
    final groups = <String, List<Placement>>{};
    for (final i in idols.values) {
      final p = layout.cards[i.id];
      if (i.category != null && p != null) groups.putIfAbsent(i.category!, () => []).add(p);
    }
    for (final entry in groups.entries) {
      final cx = entry.value.map((p) => p.x).reduce((a, b) => a + b) / entry.value.length;
      final minY = entry.value.map((p) => p.y - p.height / 2).reduce(math.min);
      final pos = worldToScreen(Offset(cx, minY), cam, size) - const Offset(0, 26);
      final color = categoryColor(entry.key);
      final tp = TextPainter(
        text: TextSpan(
          text: entry.key.toUpperCase(),
          style: TextStyle(
            fontFamily: kTitleFont,
            fontSize: 18,
            letterSpacing: 4,
            color: color.withValues(alpha: labelAlpha),
            shadows: [Shadow(color: color.withValues(alpha: labelAlpha), blurRadius: 12)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(ConstellationPainter old) => old.idols != idols || old.layout != layout || old._edges.length != _edges.length;
}

/// Minimapa: todas las cartas como puntitos y un recuadro con lo que estás viendo.
class Minimap extends StatelessWidget {
  const Minimap({
    super.key,
    required this.idols,
    required this.layout,
    required this.camera,
    required this.screen,
    required this.onJump,
  });

  final Map<String, Idol> idols;
  final BoardLayout layout;
  final ValueNotifier<CameraView> camera;
  final Size screen;
  final void Function(Offset world, {bool animate}) onJump;

  static const size = Size(150, 104);

  Rect _bounds() {
    if (layout.cards.isEmpty) return const Rect.fromLTRB(-1000, -1000, 1000, 1000);
    var r = Rect.fromCircle(center: Offset(layout.cards.values.first.x, layout.cards.values.first.y), radius: 1);
    for (final p in layout.cards.values) {
      r = r.expandToInclude(Rect.fromCircle(center: Offset(p.x, p.y), radius: p.radius));
    }
    return r.inflate(math.max(r.width, r.height) * 0.12 + 200);
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _bounds();
    final scale = math.min(size.width / bounds.width, size.height / bounds.height);
    final origin = Offset(
      (size.width - bounds.width * scale) / 2 - bounds.left * scale,
      (size.height - bounds.height * scale) / 2 - bounds.top * scale,
    );
    Offset toWorld(Offset local) => (local - origin) / scale;

    return GestureDetector(
      onTapUp: (d) => onJump(toWorld(d.localPosition), animate: true),
      onPanUpdate: (d) => onJump(toWorld(d.localPosition), animate: false),
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _MinimapPainter(idols, layout, camera, screen, scale, origin),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.idols, this.layout, this.camera, this.screen, this.scale, this.origin) : super(repaint: camera);
  final Map<String, Idol> idols;
  final BoardLayout layout;
  final ValueNotifier<CameraView> camera;
  final Size screen;
  final double scale;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in layout.cards.entries) {
      final idol = idols[e.key];
      if (idol == null) continue;
      final c = Offset(e.value.x, e.value.y) * scale + origin;
      final r = math.max(1.6, e.value.width * scale / 2);
      canvas.drawRect(Rect.fromCenter(center: c, width: r * 2, height: r * 2.6), Paint()..color = idol.rarity.color);
    }
    final view = visibleWorld(camera.value, screen);
    final rect = Rect.fromPoints(view.topLeft * scale + origin, view.bottomRight * scale + origin);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) => true;
}
