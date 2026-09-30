import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Posición de la cámara que el fondo usa para el efecto de profundidad (parallax).
class CameraView {
  const CameraView(this.center, this.zoom);
  final Offset center;
  final double zoom;
  static const zero = CameraView(Offset.zero, 1);
}

typedef ThemePaint = void Function(Canvas canvas, Size size, double t, CameraView cam);

class BoardTheme {
  const BoardTheme(this.id, this.name, this.description, this.accent, this.paint);
  final String id;
  final String name;
  final String description;

  /// Color de acento de la interfaz sobre este fondo.
  final Color accent;
  final ThemePaint paint;
}

BoardTheme themeById(String? id) => kThemes.firstWhere((t) => t.id == id, orElse: () => kThemes.first);

class BackgroundPainter extends CustomPainter {
  BackgroundPainter({required this.theme, required this.time, required this.camera})
      : super(repaint: Listenable.merge([time, camera]));

  final BoardTheme theme;
  final ValueNotifier<double> time;
  final ValueNotifier<CameraView> camera;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    theme.paint(canvas, size, time.value, camera.value);
  }

  @override
  bool shouldRepaint(BackgroundPainter old) => old.theme != theme;
}

class BoardBackground extends StatelessWidget {
  const BoardBackground({super.key, required this.theme, required this.time, required this.camera});
  final BoardTheme theme;
  final ValueNotifier<double> time;
  final ValueNotifier<CameraView> camera;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: BackgroundPainter(theme: theme, time: time, camera: camera),
          size: Size.infinite,
        ),
      );
}

// ---------------------------------------------------------------------------
// Utilidades de dibujo
// ---------------------------------------------------------------------------

void _fill(Canvas c, Size s, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter, List<double>? stops}) {
  final r = Offset.zero & s;
  c.drawRect(r, Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(r));
}

void _radial(Canvas c, Offset center, double radius, Color color) {
  c.drawCircle(
    center,
    radius,
    Paint()..shader = ui.Gradient.radial(center, radius, [color, color.withValues(alpha: 0)]),
  );
}

void _vignette(Canvas c, Size s, [double strength = 0.6]) {
  final r = Offset.zero & s;
  c.drawRect(
    r,
    Paint()
      ..shader = RadialGradient(
        radius: 0.95,
        colors: [Colors.transparent, Colors.black.withValues(alpha: strength)],
        stops: const [0.55, 1],
      ).createShader(r),
  );
}

/// Desplazamiento de una capa con profundidad [depth] (0 = quieta, 1 = pegada al tablero).
Offset _par(CameraView cam, double depth) => -cam.center * cam.zoom * depth;

double _wrap(double v, double m) => ((v % m) + m) % m;

/// Recorre partículas deterministas repartidas en la pantalla, que se envuelven al salir.
void _particles(Size s, int count, int seed, Offset shift, void Function(Offset p, math.Random r, int i) draw) {
  final rnd = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final x = _wrap(rnd.nextDouble() * s.width + shift.dx, s.width);
    final y = _wrap(rnd.nextDouble() * s.height + shift.dy, s.height);
    draw(Offset(x, y), rnd, i);
  }
}

void _stars(Canvas c, Size s, double t, CameraView cam, {int seed = 1, int count = 140, Color color = Colors.white}) {
  for (final (layer, depth) in [(0, 0.03), (1, 0.08), (2, 0.16)]) {
    _particles(s, count ~/ 3, seed + layer, _par(cam, depth), (p, r, i) {
      final tw = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * (0.7 + r.nextDouble() * 2) + i));
      final rad = 0.5 + layer * 0.45 + r.nextDouble() * 0.6;
      c.drawCircle(p, rad, Paint()..color = color.withValues(alpha: tw * (0.5 + layer * 0.25)));
      if (layer == 2 && i % 7 == 0) {
        final l = Paint()
          ..color = color.withValues(alpha: tw * 0.5)
          ..strokeWidth = 0.7;
        c.drawLine(p - Offset(rad * 4, 0), p + Offset(rad * 4, 0), l);
        c.drawLine(p - Offset(0, rad * 4), p + Offset(0, rad * 4), l);
      }
    });
  }
}

void _grid(Canvas c, Size s, CameraView cam, double cell, Paint paint, {double depth = 1}) {
  final z = math.pow(cam.zoom, 0.5).toDouble();
  final step = cell * z;
  if (step < 6) return;
  final off = _par(cam, depth * 0.5);
  for (var x = _wrap(off.dx, step); x < s.width; x += step) {
    c.drawLine(Offset(x, 0), Offset(x, s.height), paint);
  }
  for (var y = _wrap(off.dy, step); y < s.height; y += step) {
    c.drawLine(Offset(0, y), Offset(s.width, y), paint);
  }
}

void _noise(Canvas c, Size s, CameraView cam, int count, Color color, {int seed = 3, double depth = 0.5, double size = 1.2}) {
  final p = Paint()..color = color;
  _particles(s, count, seed, _par(cam, depth), (o, r, i) => c.drawCircle(o, r.nextDouble() * size + 0.3, p));
}

final Map<String, TextPainter> _glyphCache = {};

/// Glifo verde ya maquetado; [level] 0..9 = opacidad, 10 = cabeza brillante.
TextPainter _glyph(String g, int level) => _glyphCache.putIfAbsent('$g$level', () {
      final color = level == 10 ? const Color(0xFFCCFFDD) : const Color(0xFF00E676).withValues(alpha: level / 9);
      return TextPainter(
        text: TextSpan(text: g, style: TextStyle(fontSize: 13, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
    });

// ---------------------------------------------------------------------------
// Los 20 temas
// ---------------------------------------------------------------------------

final List<BoardTheme> kThemes = [
  BoardTheme('nebulosa', 'Nebulosa', 'Nubes de gas estelar y estrellas en tres capas de profundidad.', const Color(0xFFB388FF),
      (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF070318), Color(0xFF120A33), Color(0xFF04020C)]);
    final o = _par(cam, 0.05);
    _radial(c, Offset(_wrap(s.width * 0.25 + o.dx + math.sin(t * 0.05) * 40, s.width), s.height * 0.3 + o.dy * 0.3), s.longestSide * 0.55, const Color(0x55B144FF));
    _radial(c, Offset(_wrap(s.width * 0.8 + o.dx, s.width), s.height * 0.75 + o.dy * 0.3 + math.cos(t * 0.04) * 30), s.longestSide * 0.5, const Color(0x442D7BFF));
    _radial(c, Offset(s.width * 0.55, s.height * 0.5), s.longestSide * 0.35, const Color(0x22FF4FA3));
    _stars(c, s, t, cam);
  }),
  BoardTheme('galaxia', 'Galaxia Espiral', 'Una galaxia girando lentamente detrás de tu colección.', const Color(0xFF80D8FF), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF000005), Color(0xFF02010A)]);
    _stars(c, s, t, cam, seed: 9, count: 90);
    final center = Offset(s.width / 2, s.height / 2) + _par(cam, 0.02);
    _radial(c, center, s.shortestSide * 0.35, const Color(0x66FFE0B2));
    final rnd = math.Random(4);
    final rot = t * 0.03;
    for (var arm = 0; arm < 3; arm++) {
      for (var i = 0; i < 160; i++) {
        final k = i / 160;
        final a = rot + arm * 2 * math.pi / 3 + k * 5.5 + (rnd.nextDouble() - 0.5) * 0.35;
        final r = s.shortestSide * (0.04 + k * 0.62) + rnd.nextDouble() * 14;
        final p = center + Offset(math.cos(a) * r * 1.25, math.sin(a) * r * 0.75);
        final col = Color.lerp(const Color(0xFFFFE0B2), const Color(0xFF7FB2FF), k)!;
        c.drawCircle(p, 0.6 + rnd.nextDouble() * 1.4, Paint()..color = col.withValues(alpha: 0.75 * (1 - k * 0.6)));
      }
    }
    _radial(c, center, 24, const Color(0xFFFFF3E0));
  }),
  BoardTheme('terciopelo', 'Terciopelo Carmesí', 'Terciopelo rojo profundo, como un estuche de joyería.', const Color(0xFFFFD36B), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF5A0712), Color(0xFF2A0208)]);
    final o = _par(cam, 0.2);
    for (var i = -2; i < 14; i++) {
      final x = _wrap(i * 140 + o.dx, s.width + 280) - 140;
      c.drawRect(
        Rect.fromLTWH(x, 0, 140, s.height),
        Paint()
          ..shader = ui.Gradient.linear(Offset(x, 0), Offset(x + 140, 0),
              [const Color(0x00000000), const Color(0x22FF6B6B), const Color(0x33000000)], [0, 0.5, 1]),
      );
    }
    _radial(c, Offset(s.width / 2, s.height * 0.4), s.longestSide * 0.6, const Color(0x33FF4D4D));
    _noise(c, s, cam, 500, const Color(0x14FFFFFF), depth: 0.3, size: 0.7);
    _vignette(c, s, 0.75);
  }),
  BoardTheme('corcho', 'Tablero de Corcho', 'Corcho cálido, como un tablero donde clavás tus tesoros.', const Color(0xFFFFB74D), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFFB07A45), Color(0xFF8E5A2E)]);
    _noise(c, s, cam, 1400, const Color(0x55442200), seed: 11, depth: 1, size: 2.2);
    _noise(c, s, cam, 900, const Color(0x33FFE0B2), seed: 12, depth: 1, size: 1.4);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..shader = ui.Gradient.linear(Offset.zero, Offset(s.width, s.height), [const Color(0xFF5D3A1A), const Color(0xFF3E2410)]);
    c.drawRect((Offset.zero & s).deflate(9), frame);
    _vignette(c, s, 0.45);
  }),
  BoardTheme('album', 'Álbum Filatélico', 'Hojas de álbum antiguo con cuadrícula y bandas de sujeción.', const Color(0xFF8B1E1E), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFFF3EAD3), Color(0xFFE4D6B5)]);
    _grid(c, s, cam, 24, Paint()
      ..color = const Color(0x22806040)
      ..strokeWidth = 0.6);
    final z = math.pow(cam.zoom, 0.5).toDouble();
    final step = 380 * z;
    final off = _par(cam, 0.5);
    final band = Paint()..color = const Color(0x18000000);
    for (var y = _wrap(off.dy, step); y < s.height; y += step) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 26 * z), band);
      c.drawLine(Offset(0, y), Offset(s.width, y), Paint()..color = const Color(0x33806040));
    }
    _noise(c, s, cam, 300, const Color(0x22704010), depth: 0.5);
    _vignette(c, s, 0.35);
  }),
  BoardTheme('pergamino', 'Mapa de Pergamino', 'Pergamino envejecido con rosa de los vientos y rutas.', const Color(0xFF6D3B12), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFFE6CE9A), Color(0xFFC9A263)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final o = _par(cam, 0.3);
    final rnd = math.Random(21);
    for (var i = 0; i < 9; i++) {
      _radial(c, Offset(_wrap(rnd.nextDouble() * s.width + o.dx, s.width), _wrap(rnd.nextDouble() * s.height + o.dy, s.height)),
          60 + rnd.nextDouble() * 120, const Color(0x307A4A12));
    }
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x557A4A12);
    for (var i = 0; i < 5; i++) {
      final path = Path()..moveTo(o.dx % s.width - 200, s.height * (0.15 + i * 0.18) + o.dy % 100);
      for (var x = 0.0; x < s.width + 400; x += 30) {
        path.lineTo(o.dx % s.width - 200 + x, s.height * (0.15 + i * 0.18) + o.dy % 100 + math.sin(x * 0.01 + i) * 30);
      }
      c.drawPath(path, ink);
    }
    final cc = Offset(s.width - 90, s.height - 110);
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4 + t * 0.02;
      final len = k.isEven ? 60.0 : 34.0;
      c.drawPath(
        Path()
          ..moveTo(cc.dx, cc.dy)
          ..lineTo(cc.dx + math.cos(a + 0.12) * len * 0.3, cc.dy + math.sin(a + 0.12) * len * 0.3)
          ..lineTo(cc.dx + math.cos(a) * len, cc.dy + math.sin(a) * len)
          ..close(),
        Paint()..color = const Color(0x807A4A12),
      );
    }
    c.drawCircle(cc, 40, ink);
    _vignette(c, s, 0.5);
  }),
  BoardTheme('marmol', 'Mármol Negro', 'Mármol negro con vetas de oro.', const Color(0xFFD4AF37), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF151515), Color(0xFF050505)], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final o = _par(cam, 0.25);
    final rnd = math.Random(5);
    for (var i = 0; i < 14; i++) {
      final gold = i % 3 == 0;
      final start = Offset(_wrap(rnd.nextDouble() * s.width + o.dx, s.width), _wrap(rnd.nextDouble() * s.height + o.dy, s.height));
      final path = Path()..moveTo(start.dx, start.dy);
      var p = start;
      var ang = rnd.nextDouble() * math.pi * 2;
      for (var k = 0; k < 16; k++) {
        ang += (rnd.nextDouble() - 0.5) * 0.9;
        final n = p + Offset(math.cos(ang), math.sin(ang)) * (20 + rnd.nextDouble() * 30);
        path.quadraticBezierTo(p.dx + (rnd.nextDouble() - 0.5) * 20, p.dy + (rnd.nextDouble() - 0.5) * 20, n.dx, n.dy);
        p = n;
      }
      final shimmer = gold ? 0.6 + 0.4 * math.sin(t * 0.8 + i) : 1.0;
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = gold ? 1.6 : 0.8 + rnd.nextDouble() * 2
          ..color = gold ? const Color(0xFFD4AF37).withValues(alpha: 0.7 * shimmer) : Colors.white.withValues(alpha: 0.06 + rnd.nextDouble() * 0.06),
      );
    }
    _vignette(c, s, 0.5);
  }),
  BoardTheme('aurora', 'Aurora Boreal', 'Cortinas de luz verde y violeta sobre montañas nevadas.', const Color(0xFF69F0AE), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF020B1A), Color(0xFF06243A), Color(0xFF0A1420)]);
    _stars(c, s, t, cam, seed: 13, count: 90);
    final o = _par(cam, 0.04);
    for (var band = 0; band < 3; band++) {
      final color = [const Color(0xFF3DFFB0), const Color(0xFF7C4DFF), const Color(0xFF18FFFF)][band];
      for (var x = -20.0; x < s.width + 20; x += 6) {
        final xx = x + o.dx;
        final y = s.height * (0.25 + band * 0.09) + math.sin(xx * 0.006 + t * 0.35 + band) * 50 + math.sin(xx * 0.017 - t * 0.5) * 18;
        final h = 120 + 80 * math.sin(xx * 0.01 + t * 0.6 + band * 2);
        final a = 0.10 + 0.08 * math.sin(xx * 0.03 + t);
        c.drawRect(
          Rect.fromLTWH(x, y, 7, h),
          Paint()..shader = ui.Gradient.linear(Offset(x, y), Offset(x, y + h), [color.withValues(alpha: 0), color.withValues(alpha: a), color.withValues(alpha: 0)], [0, 0.3, 1]),
        );
      }
    }
    final m = _par(cam, 0.1);
    final path = Path()..moveTo(0, s.height);
    for (var x = 0.0; x <= s.width; x += 10) {
      final xx = x + m.dx;
      path.lineTo(x, s.height * 0.82 - (math.sin(xx * 0.004) * 60 + math.sin(xx * 0.013) * 25).abs());
    }
    path
      ..lineTo(s.width, s.height)
      ..close();
    c.drawPath(path, Paint()..color = const Color(0xFF030A12));
  }),
  BoardTheme('oceano', 'Océano Profundo', 'Luz filtrándose en el fondo del mar, con burbujas.', const Color(0xFF4DD0E1), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF0B4F6C), Color(0xFF052A45), Color(0xFF010D1C)]);
    final o = _par(cam, 0.08);
    for (var i = 0; i < 7; i++) {
      final x = _wrap(i * s.width / 6 + o.dx + math.sin(t * 0.2 + i) * 30, s.width);
      c.drawPath(
        Path()
          ..moveTo(x - 20, 0)
          ..lineTo(x + 20, 0)
          ..lineTo(x + 140, s.height)
          ..lineTo(x - 30, s.height)
          ..close(),
        Paint()..shader = ui.Gradient.linear(Offset(x, 0), Offset(x, s.height), [const Color(0x2280DEEA), const Color(0x0080DEEA)]),
      );
    }
    _particles(s, 45, 17, _par(cam, 0.15) + Offset(0, -t * 30), (p, r, i) {
      final wob = math.sin(t * 2 + i) * 4;
      c.drawCircle(p + Offset(wob, 0), 1.5 + r.nextDouble() * 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = Colors.white.withValues(alpha: 0.35));
    });
    _vignette(c, s, 0.5);
  }),
  BoardTheme('brasas', 'Brasas', 'Chispas que suben desde un fuego invisible.', const Color(0xFFFF9100), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF0A0200), Color(0xFF1A0500), Color(0xFF3A0C00)]);
    _radial(c, Offset(s.width / 2, s.height * 1.1), s.longestSide * 0.7, Color.fromRGBO(255, 80, 0, 0.35 + 0.08 * math.sin(t * 3)));
    _particles(s, 90, 23, _par(cam, 0.12) + Offset(0, -t * 60), (p, r, i) {
      final flick = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 6 + i * 1.3));
      final sway = math.sin(t * 1.5 + i) * 10;
      final col = Color.lerp(const Color(0xFFFFD54F), const Color(0xFFFF3D00), r.nextDouble())!;
      c.drawCircle(p + Offset(sway, 0), 0.8 + r.nextDouble() * 1.8,
          Paint()
            ..color = col.withValues(alpha: flick)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    });
    _vignette(c, s, 0.4);
  }),
  BoardTheme('synthwave', 'Synthwave', 'Atardecer retro de los 80 con grilla de neón en movimiento.', const Color(0xFFFF4FD8), (c, s, t, cam) {
    final horizon = s.height * 0.55;
    _fill(c, s, const [Color(0xFF12002B), Color(0xFF4A0060), Color(0xFFFF4F7B), Color(0xFF12002B)], stops: const [0, 0.35, 0.55, 0.551]);
    _stars(c, Size(s.width, horizon), t, cam, seed: 31, count: 60);
    final sun = Offset(s.width / 2, horizon - 10);
    final r = s.shortestSide * 0.22;
    c.save();
    c.clipRect(Rect.fromLTRB(0, 0, s.width, horizon));
    c.drawCircle(sun, r, Paint()..shader = ui.Gradient.linear(sun - Offset(0, r), sun + Offset(0, r), [const Color(0xFFFFE259), const Color(0xFFFF2E93)]));
    for (var i = 0; i < 7; i++) {
      final y = sun.dy - r * 0.05 + i * r * 0.14;
      c.drawRect(Rect.fromLTWH(sun.dx - r, y, r * 2, 2 + i * 1.2), Paint()..color = const Color(0xFF4A0060));
    }
    c.restore();
    final line = Paint()
      ..color = const Color(0xFFFF4FD8)
      ..strokeWidth = 1.2;
    final o = _par(cam, 0.2);
    for (var i = -20; i <= 20; i++) {
      final x0 = s.width / 2 + (i * 40 + _wrap(o.dx, 40)) * 0.2;
      final x1 = s.width / 2 + (i * 40 + _wrap(o.dx, 40)) * 4;
      c.drawLine(Offset(x0, horizon), Offset(x1, s.height), line);
    }
    final scroll = _wrap(t * 0.4 + o.dy * 0.002, 1);
    for (var k = 0; k < 14; k++) {
      final d = (k + scroll) / 14;
      final y = horizon + (s.height - horizon) * d * d;
      c.drawLine(Offset(0, y), Offset(s.width, y), line..color = const Color(0xFFFF4FD8).withValues(alpha: 0.3 + 0.7 * d));
    }
  }),
  BoardTheme('matrix', 'Código', 'Lluvia de símbolos verdes, estilo terminal.', const Color(0xFF00E676), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF000000), Color(0xFF001A08)]);
    const glyphs = 'アイウエオカキクケコサシスセソ0123456789ÍDOLS';
    final colW = 18.0;
    final o = _par(cam, 0.1);
    final rnd = math.Random(3);
    final cols = (s.width / colW).ceil() + 1;
    for (var col = 0; col < cols; col++) {
      final speed = 60 + rnd.nextDouble() * 120;
      final len = 8 + rnd.nextInt(14);
      final x = _wrap(col * colW + o.dx, cols * colW) - colW;
      final head = _wrap(t * speed + rnd.nextDouble() * s.height * 2, s.height + len * colW);
      for (var k = 0; k < len; k++) {
        final y = head - k * colW;
        if (y < -colW || y > s.height) continue;
        final g = glyphs[(col * 7 + k * 3 + (t * 4).floor()) % glyphs.length];
        _glyph(g, k == 0 ? 10 : (9 * (1 - k / len)).round()).paint(c, Offset(x, y));
      }
    }
    _vignette(c, s, 0.5);
  }),
  BoardTheme('olimpo', 'Olimpo', 'Cielo dorado entre nubes: el hogar de los dioses.', const Color(0xFFFFE082), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFFFFE9B0), Color(0xFFFFC56B), Color(0xFFE38B4C)]);
    final sun = Offset(s.width * 0.5, -s.height * 0.1);
    for (var i = 0; i < 12; i++) {
      final a = math.pi / 2 + (i - 6) * 0.13 + math.sin(t * 0.1 + i) * 0.02;
      c.drawPath(
        Path()
          ..moveTo(sun.dx, sun.dy)
          ..lineTo(sun.dx + math.cos(a - 0.03) * s.longestSide * 1.5, sun.dy + math.sin(a - 0.03) * s.longestSide * 1.5)
          ..lineTo(sun.dx + math.cos(a + 0.03) * s.longestSide * 1.5, sun.dy + math.sin(a + 0.03) * s.longestSide * 1.5)
          ..close(),
        Paint()..color = const Color(0x18FFFFFF),
      );
    }
    for (final (depth, alpha, seed, n) in [(0.06, 0.55, 1, 7), (0.14, 0.75, 2, 6), (0.28, 0.95, 3, 5)]) {
      final o = _par(cam, depth) + Offset(t * 6 * depth * 10, 0);
      final rnd = math.Random(seed);
      for (var i = 0; i < n; i++) {
        final base = Offset(_wrap(rnd.nextDouble() * s.width + o.dx, s.width + 300) - 150, s.height * (0.35 + rnd.nextDouble() * 0.7) + o.dy * 0.2);
        for (var k = 0; k < 6; k++) {
          final p = base + Offset((k - 3) * 38.0, -math.sin(k / 5 * math.pi) * 30);
          c.drawCircle(p, 40 + rnd.nextDouble() * 20, Paint()..color = Colors.white.withValues(alpha: alpha * 0.5));
        }
      }
    }
  }),
  BoardTheme('madera', 'Madera Noble', 'Tablones de madera oscura con veta, como una vitrina.', const Color(0xFFFFCC80), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF3B2314), Color(0xFF24150B)]);
    final z = math.pow(cam.zoom, 0.5).toDouble();
    final plank = 150 * z;
    final o = _par(cam, 0.5);
    final rnd = math.Random(8);
    for (var y = _wrap(o.dy, plank) - plank; y < s.height; y += plank) {
      final idx = ((y - o.dy) / plank).round();
      final shade = (idx * 37 % 5) / 5;
      c.drawRect(Rect.fromLTWH(0, y, s.width, plank), Paint()..color = Color.lerp(const Color(0x00000000), const Color(0x22000000), shade)!);
      for (var k = 0; k < 7; k++) {
        final gy = y + plank * (k + 0.5) / 7;
        final path = Path()..moveTo(0, gy);
        for (var x = 0.0; x < s.width; x += 20) {
          path.lineTo(x, gy + math.sin((x - o.dx) * 0.01 + k + idx) * 3 * z);
        }
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 + rnd.nextDouble()
          ..color = const Color(0x22D7A86E));
      }
      c.drawLine(Offset(0, y), Offset(s.width, y), Paint()
        ..color = const Color(0xAA120A04)
        ..strokeWidth = 2.5);
    }
    _radial(c, Offset(s.width / 2, s.height * 0.3), s.longestSide * 0.6, const Color(0x22FFCC80));
    _vignette(c, s, 0.6);
  }),
  BoardTheme('catedral', 'Catedral', 'Haces de luz sagrada cayendo sobre la penumbra, con polvo flotando.', const Color(0xFFFFF59D), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF1B1622), Color(0xFF0B0910)]);
    final o = _par(cam, 0.05);
    for (var i = 0; i < 5; i++) {
      final x = _wrap(s.width * (0.1 + i * 0.22) + o.dx, s.width + 200) - 100;
      final a = 0.08 + 0.05 * math.sin(t * 0.4 + i * 1.7);
      final color = [const Color(0xFFFFF59D), const Color(0xFF90CAF9), const Color(0xFFF48FB1), const Color(0xFFFFCC80), const Color(0xFFB39DDB)][i];
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 50, 0)
          ..lineTo(x + 260, s.height)
          ..lineTo(x + 90, s.height)
          ..close(),
        Paint()..shader = ui.Gradient.linear(Offset(x, 0), Offset(x + 150, s.height), [color.withValues(alpha: a * 2), color.withValues(alpha: 0)]),
      );
    }
    _particles(s, 70, 41, _par(cam, 0.1) + Offset(math.sin(t * 0.3) * 20, t * 6), (p, r, i) {
      c.drawCircle(p, 0.6 + r.nextDouble(), Paint()..color = const Color(0xFFFFF8E1).withValues(alpha: 0.2 + 0.4 * (0.5 + 0.5 * math.sin(t + i))));
    });
    _vignette(c, s, 0.6);
  }),
  BoardTheme('plano', 'Plano Técnico', 'Papel de plano azul con cuadrícula técnica.', const Color(0xFFE3F2FD), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF0D47A1), Color(0xFF0A3A85)]);
    _grid(c, s, cam, 20, Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 0.5);
    _grid(c, s, cam, 100, Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 1);
    final o = _par(cam, 0.5);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    c.drawCircle(Offset(_wrap(s.width * 0.8 + o.dx, s.width), _wrap(s.height * 0.2 + o.dy, s.height)), 90, ink);
    c.drawCircle(Offset(_wrap(s.width * 0.2 + o.dx, s.width), _wrap(s.height * 0.75 + o.dy, s.height)), 140, ink);
    _vignette(c, s, 0.35);
  }),
  BoardTheme('tormenta', 'Tormenta', 'Nubes pesadas, lluvia y relámpagos repentinos.', const Color(0xFFB3E5FC), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF10141C), Color(0xFF1C222E), Color(0xFF0A0D12)]);
    final cycle = t % 7.0;
    final flash = cycle < 0.12 ? 0.5 : (cycle > 0.22 && cycle < 0.3 ? 0.35 : 0.0);
    if (flash > 0) {
      c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE3F2FD).withValues(alpha: flash * 0.5));
      final rnd = math.Random((t / 7).floor());
      var p = Offset(s.width * (0.2 + rnd.nextDouble() * 0.6), 0);
      final bolt = Path()..moveTo(p.dx, p.dy);
      while (p.dy < s.height * 0.6) {
        p += Offset((rnd.nextDouble() - 0.5) * 60, 20 + rnd.nextDouble() * 30);
        bolt.lineTo(p.dx, p.dy);
      }
      c.drawPath(bolt, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: flash * 2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    final o = _par(cam, 0.05);
    final rnd = math.Random(2);
    for (var i = 0; i < 14; i++) {
      _radial(c, Offset(_wrap(rnd.nextDouble() * s.width + o.dx + t * 5, s.width + 200) - 100, rnd.nextDouble() * s.height * 0.4), 120 + rnd.nextDouble() * 120,
          const Color(0x55303848));
    }
    final rain = Paint()
      ..color = const Color(0x40B3E5FC)
      ..strokeWidth = 1;
    _particles(s, 160, 5, _par(cam, 0.2) + Offset(t * 120, t * 700), (p, r, i) => c.drawLine(p, p + const Offset(-4, 16), rain));
  }),
  BoardTheme('sakura', 'Sakura Nocturno', 'Pétalos de cerezo cayendo en una noche índigo.', const Color(0xFFFF80AB), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF1A1033), Color(0xFF2B1640), Color(0xFF120A1E)]);
    _radial(c, Offset(s.width * 0.8, s.height * 0.18), 70, const Color(0xCCFFF3E0));
    _radial(c, Offset(s.width * 0.8, s.height * 0.18), 200, const Color(0x22FFE0F0));
    _particles(s, 60, 71, _par(cam, 0.12) + Offset(t * 25, t * 45), (p, r, i) {
      c.save();
      c.translate(p.dx + math.sin(t + i) * 12, p.dy);
      c.rotate(t * (0.5 + r.nextDouble()) + i);
      final sz = 3.0 + r.nextDouble() * 4;
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: sz * 2, height: sz),
          Paint()..color = Color.lerp(const Color(0xFFFFC1D9), const Color(0xFFFF80AB), r.nextDouble())!.withValues(alpha: 0.85));
      c.restore();
    });
    _vignette(c, s, 0.4);
  }),
  BoardTheme('glaciar', 'Glaciar', 'Hielo azul y una nevada suave.', const Color(0xFF80D8FF), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFFBFE9F7), Color(0xFF5FA8C9), Color(0xFF1D4E6B)]);
    final o = _par(cam, 0.15);
    final rnd = math.Random(6);
    for (var i = 0; i < 10; i++) {
      final x = _wrap(rnd.nextDouble() * s.width + o.dx, s.width + 300) - 150;
      final y = s.height * (0.6 + rnd.nextDouble() * 0.4);
      final w = 80 + rnd.nextDouble() * 160, h = 120 + rnd.nextDouble() * 220;
      c.drawPath(
        Path()
          ..moveTo(x, s.height)
          ..lineTo(x + w * 0.3, y - h)
          ..lineTo(x + w * 0.55, y - h * 0.7)
          ..lineTo(x + w, s.height)
          ..close(),
        Paint()..color = const Color(0x33FFFFFF),
      );
    }
    _particles(s, 120, 19, _par(cam, 0.2) + Offset(t * 12, t * 40), (p, r, i) {
      c.drawCircle(p + Offset(math.sin(t + i) * 8, 0), 1 + r.nextDouble() * 2.2, Paint()..color = Colors.white.withValues(alpha: 0.8));
    });
  }),
  BoardTheme('salon', 'Salón de la Fama', 'Focos que barren un salón oscuro con piso dorado.', const Color(0xFFFFD740), (c, s, t, cam) {
    _fill(c, s, const [Color(0xFF0B0B0F), Color(0xFF15131A), Color(0xFF2A1F0A)], stops: const [0, 0.7, 1]);
    for (var i = 0; i < 3; i++) {
      final origin = Offset(s.width * (0.2 + i * 0.3), -20);
      final a = math.pi / 2 + math.sin(t * 0.35 + i * 2.1) * 0.45;
      final len = s.longestSide * 1.3;
      final p1 = origin + Offset(math.cos(a - 0.12), math.sin(a - 0.12)) * len;
      final p2 = origin + Offset(math.cos(a + 0.12), math.sin(a + 0.12)) * len;
      c.drawPath(
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close(),
        Paint()..shader = ui.Gradient.linear(origin, origin + Offset(math.cos(a), math.sin(a)) * len, [const Color(0x40FFF8E1), const Color(0x00FFF8E1)]),
      );
      final spot = origin + Offset(math.cos(a), math.sin(a)) * (s.height * 0.95);
      _radial(c, Offset(spot.dx, s.height * 0.92), 120, const Color(0x33FFD740));
    }
    _noise(c, s, cam, 140, const Color(0x55FFD740), seed: 55, depth: 0.2, size: 0.8);
    _vignette(c, s, 0.5);
  }),
];
