import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/catalog.dart';

// Geometría fija de la estampilla (en unidades del tablero).
const double kPerfRadius = 5.5;
const Rect kWindow = Rect.fromLTRB(22, 22, kCardW - 22, kCardH - 78);
const Rect kBand = Rect.fromLTRB(16, kCardH - 72, kCardW - 16, kCardH - 16);

Path? _stampPath;

/// Contorno con los agujeritos del dentado de una estampilla. Se calcula una vez.
Path stampPath() {
  if (_stampPath != null) return _stampPath!;
  const r = kPerfRadius;
  const w = kCardW, h = kCardH;
  var shape = Path()..addRect(const Rect.fromLTWH(0, 0, w, h));
  final holes = Path();
  void edge(double length, Offset Function(double) at) {
    final n = (length / (r * 2.7)).round();
    final step = length / n;
    for (var i = 0; i <= n; i++) {
      holes.addOval(Rect.fromCircle(center: at(i * step), radius: r));
    }
  }

  edge(w, (d) => Offset(d, 0));
  edge(w, (d) => Offset(d, h));
  edge(h, (d) => Offset(0, d));
  edge(h, (d) => Offset(w, d));
  shape = Path.combine(PathOperation.difference, shape, holes);
  return _stampPath = shape;
}

class StampClipper extends CustomClipper<Path> {
  const StampClipper();
  @override
  Path getClip(Size size) => stampPath();
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Utilidad: 0..1 suave entre [a] y [b].
double smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Color rarityGlowColor(Rarity rarity, double t) {
  if (!rarity.rainbow) return rarity.color;
  return HSVColor.fromAHSV(1, (t * 40) % 360, 0.75, 1).toColor();
}

// ---------------------------------------------------------------------------
// Brillo exterior
// ---------------------------------------------------------------------------

class GlowPainter extends CustomPainter {
  GlowPainter({required this.rarity, required this.time, this.selected = false, this.boost = 1})
      : super(repaint: time);

  final Rarity rarity;
  final ValueNotifier<double> time;
  final bool selected;
  final double boost;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final path = stampPath();
    // Sombra de apoyo.
    canvas.drawPath(
      path.shift(const Offset(4, 9)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    final pulse = 0.6 + 0.4 * math.sin(t * rarity.pulseSpeed * 2.1);
    final strength = (rarity.glow * pulse * boost).clamp(0.0, 1.0);
    if (strength > 0.02) {
      final color = rarityGlowColor(rarity, t);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.85 * strength)
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, 10 + 16 * strength),
      );
      if (rarity.index >= Rarity.legendary.index) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35 * strength)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 4),
        );
      }
    }
    if (selected) {
      final a = 0.55 + 0.45 * math.sin(t * 6);
      canvas.drawRect(
        const Rect.fromLTWH(-10, -10, kCardW + 20, kCardH + 20),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(GlowPainter old) =>
      old.rarity != rarity || old.selected != selected || old.boost != boost;
}

// ---------------------------------------------------------------------------
// Papel, filetes y ornamentos
// ---------------------------------------------------------------------------

class PaperPainter extends CustomPainter {
  PaperPainter({required this.frame, required this.time, required this.animate})
      : super(repaint: animate && frame.fx != FrameFx.none && frame.fx != FrameFx.aged ? time : null);

  final FrameStyle frame;
  final ValueNotifier<double> time;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animate ? time.value : 0.0;
    const full = Rect.fromLTWH(0, 0, kCardW, kCardH);
    final colors = frame.paper.length == 1 ? [frame.paper.first, frame.paper.first] : frame.paper;
    canvas.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(kCardW, kCardH),
          colors,
          [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
        ),
    );
    _fx(canvas, t);
    _borders(canvas, t);
    _ornaments(canvas, t);
  }

  void _fx(Canvas canvas, double t) {
    final rnd = math.Random(frame.id.hashCode);
    switch (frame.fx) {
      case FrameFx.none:
        break;
      case FrameFx.aged:
        for (var i = 0; i < 5; i++) {
          final c = Offset(rnd.nextDouble() * kCardW, rnd.nextDouble() * kCardH);
          canvas.drawCircle(
            c,
            30 + rnd.nextDouble() * 50,
            Paint()
              ..shader = ui.Gradient.radial(c, 30 + rnd.nextDouble() * 50, [
                const Color(0x40603A10),
                const Color(0x00603A10),
              ]),
          );
        }
        final speck = Paint()..color = const Color(0x55402000);
        for (var i = 0; i < 90; i++) {
          canvas.drawCircle(Offset(rnd.nextDouble() * kCardW, rnd.nextDouble() * kCardH), rnd.nextDouble() * 0.9, speck);
        }
      case FrameFx.cosmic:
        for (var i = 0; i < 70; i++) {
          final o = Offset(rnd.nextDouble() * kCardW, rnd.nextDouble() * kCardH);
          final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (1 + rnd.nextDouble() * 2) + i));
          canvas.drawCircle(o, 0.4 + rnd.nextDouble() * 1.1, Paint()..color = Colors.white.withValues(alpha: tw));
        }
        final c = Offset(kCardW * (0.5 + 0.3 * math.sin(t * 0.2)), kCardH * 0.4);
        canvas.drawCircle(
          c,
          140,
          Paint()
            ..shader = ui.Gradient.radial(c, 140, [const Color(0x559D4EDD), const Color(0x00000000)]),
        );
      case FrameFx.fire:
        for (var i = 0; i < 3; i++) {
          final flicker = 0.75 + 0.25 * math.sin(t * (5 + i * 2.3) + i);
          final c = Offset(kCardW * (0.2 + 0.3 * i), kCardH + 20);
          canvas.drawCircle(
            c,
            160 * flicker,
            Paint()
              ..shader = ui.Gradient.radial(c, 160 * flicker, [
                const Color(0xAAFF5A00),
                const Color(0x44FF1E00),
                const Color(0x00000000),
              ], [0, 0.5, 1]),
          );
        }
      case FrameFx.neon:
        break;
      case FrameFx.holo:
        _rainbow(canvas, t, 0.55, BlendMode.srcOver);
      case FrameFx.frost:
        for (final corner in const [Offset(0, 0), Offset(kCardW, 0), Offset(0, kCardH), Offset(kCardW, kCardH)]) {
          canvas.drawCircle(
            corner,
            110,
            Paint()..shader = ui.Gradient.radial(corner, 110, [const Color(0xCCFFFFFF), const Color(0x00FFFFFF)]),
          );
        }
        for (var i = 0; i < 26; i++) {
          final o = Offset(rnd.nextDouble() * kCardW, rnd.nextDouble() * kCardH);
          final a = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 2 + i * 1.7));
          _sparkle(canvas, o, 2 + rnd.nextDouble() * 3, Colors.white.withValues(alpha: a));
        }
    }
  }

  void _rainbow(Canvas canvas, double t, double alpha, BlendMode mode) {
    final shift = (t * 0.15) % 1.0;
    final colors = [
      for (final h in [0, 60, 120, 180, 240, 300, 360])
        HSVColor.fromAHSV(alpha, (h + shift * 360) % 360, 0.45, 1).toColor(),
    ];
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, kCardW, kCardH),
      Paint()
        ..blendMode = mode
        ..shader = ui.Gradient.linear(
          Offset(-kCardW * shift, 0),
          Offset(kCardW * (1.5 - shift), kCardH),
          colors,
          [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
          TileMode.mirror,
        ),
    );
  }

  void _borders(Canvas canvas, double t) {
    final win = kWindow.inflate(3);
    final outer = const Rect.fromLTWH(10, 10, kCardW - 20, kCardH - 20);
    if (frame.fx == FrameFx.neon) {
      final flick = 0.8 + 0.2 * math.sin(t * 13) * math.sin(t * 7.3);
      for (final (rect, color) in [(outer, frame.border2), (win, frame.border)]) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = color.withValues(alpha: 0.6 * flick)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Color.lerp(color, Colors.white, 0.5)!.withValues(alpha: flick),
        );
      }
      return;
    }
    canvas.drawRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = frame.border,
    );
    canvas.drawRect(
      outer.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = frame.border2,
    );
    canvas.drawRect(
      win,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = frame.border,
    );
    canvas.drawRect(
      win.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = frame.border2,
    );
  }

  void _ornaments(Canvas canvas, double t) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = frame.border;
    final fill = Paint()..color = frame.border;
    const corners = [Offset(16, 16), Offset(kCardW - 16, 16), Offset(16, kCardH - 16), Offset(kCardW - 16, kCardH - 16)];
    switch (frame.ornament) {
      case Ornament.none:
        break;
      case Ornament.corners:
        for (final c in corners) {
          final sx = c.dx < kCardW / 2 ? 1.0 : -1.0, sy = c.dy < kCardH / 2 ? 1.0 : -1.0;
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy + 14 * sy)
              ..lineTo(c.dx, c.dy)
              ..lineTo(c.dx + 14 * sx, c.dy),
            stroke..strokeWidth = 2,
          );
          canvas.drawCircle(c + Offset(4 * sx, 4 * sy), 1.6, fill);
        }
      case Ornament.filigree:
        for (final c in corners) {
          final sx = c.dx < kCardW / 2 ? 1.0 : -1.0, sy = c.dy < kCardH / 2 ? 1.0 : -1.0;
          final path = Path()
            ..moveTo(c.dx, c.dy + 22 * sy)
            ..cubicTo(c.dx, c.dy + 6 * sy, c.dx + 6 * sx, c.dy, c.dx + 22 * sx, c.dy)
            ..moveTo(c.dx + 5 * sx, c.dy + 12 * sy)
            ..cubicTo(c.dx + 12 * sx, c.dy + 12 * sy, c.dx + 12 * sx, c.dy + 5 * sy, c.dx + 7 * sx, c.dy + 5 * sy);
          canvas.drawPath(path, stroke);
          canvas.drawCircle(c + Offset(3 * sx, 3 * sy), 2.2, fill);
        }
        for (final m in const [Offset(kCardW / 2, 12), Offset(12, kCardH / 2), Offset(kCardW - 12, kCardH / 2)]) {
          _diamond(canvas, m, 4, fill);
        }
      case Ornament.stars:
        for (final c in corners) {
          _star(canvas, c + Offset(c.dx < kCardW / 2 ? 2 : -2, c.dy < kCardH / 2 ? 2 : -2), 6, fill);
        }
      case Ornament.circuit:
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = frame.border.withValues(alpha: 0.8);
        for (var i = 0; i < 6; i++) {
          final x = 30.0 + i * 36;
          canvas.drawLine(Offset(x, 10), Offset(x, 17), p);
          canvas.drawCircle(Offset(x, 18), 1.6, Paint()..color = frame.border2);
          canvas.drawLine(Offset(x + 10, kCardH - 10), Offset(x + 10, kCardH - 15), p);
        }
        final pulse = (t * 0.5) % 1.0;
        canvas.drawCircle(
          Offset(10 + (kCardW - 20) * pulse, 10),
          2.2,
          Paint()
            ..color = frame.border2
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      case Ornament.flames:
        final flame = Paint()..color = frame.border2.withValues(alpha: 0.9);
        for (var i = 0; i < 9; i++) {
          final x = 24.0 + i * 24;
          final hgt = 9 + 5 * math.sin(t * 6 + i * 1.3);
          final base = kCardH - 12;
          canvas.drawPath(
            Path()
              ..moveTo(x - 5, base)
              ..quadraticBezierTo(x - 6, base - hgt * 0.6, x, base - hgt)
              ..quadraticBezierTo(x + 6, base - hgt * 0.6, x + 5, base)
              ..close(),
            flame,
          );
        }
      case Ornament.crystals:
        for (final c in corners) {
          _diamond(canvas, c, 7, Paint()..color = frame.border.withValues(alpha: 0.85));
          _diamond(canvas, c, 3.5, Paint()..color = Colors.white);
        }
      case Ornament.laurel:
        final leaf = Paint()..color = frame.border2.withValues(alpha: 0.9);
        for (final side in [-1.0, 1.0]) {
          for (var i = 0; i < 6; i++) {
            final cx = kCardW / 2 + side * (12 + i * 11);
            final cy = 16.0 + (i.isEven ? -1.5 : 1.5);
            canvas.save();
            canvas.translate(cx, cy);
            canvas.rotate(side * 1.25 + (i.isEven ? -0.35 : 0.35));
            canvas.drawOval(const Rect.fromLTWH(-2, -4.5, 4, 9), leaf);
            canvas.restore();
          }
        }
        canvas.drawCircle(const Offset(kCardW / 2, 16), 2.2, Paint()..color = frame.border2);
      case Ornament.runes:
        final r = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = frame.border.withValues(alpha: 0.75);
        final rnd = math.Random(7);
        for (var i = 0; i < 11; i++) {
          final x = 26.0 + i * 19;
          for (final y in const [13.0, kCardH - 19]) {
            final path = Path()..moveTo(x, y);
            path.lineTo(x, y + 7);
            path.moveTo(x, y + rnd.nextInt(4).toDouble());
            path.lineTo(x + (rnd.nextBool() ? 4 : -4), y + 2 + rnd.nextInt(4));
            canvas.drawPath(path, r);
          }
        }
    }
  }

  static void _diamond(Canvas canvas, Offset c, double r, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * 0.7, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * 0.7, c.dy)
        ..close(),
      paint,
    );
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.42;
      final o = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  bool shouldRepaint(PaperPainter old) => old.frame != frame || old.animate != animate;
}

void _sparkle(Canvas canvas, Offset c, double r, Color color) {
  final p = Paint()
    ..color = color
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), p);
  canvas.drawLine(c - Offset(0, r), c + Offset(0, r), p);
}

// ---------------------------------------------------------------------------
// Sombras vivas sobre la imagen, reflejo y holograma
// ---------------------------------------------------------------------------

class ShadePainter extends CustomPainter {
  ShadePainter({
    required this.rarity,
    required this.frame,
    required this.time,
    required this.animate,
    this.tilt,
    this.seed = 0,
  }) : super(repaint: animate ? Listenable.merge([time, ?tilt]) : null);

  final Rarity rarity;
  final FrameStyle frame;
  final ValueNotifier<double> time;
  final ValueNotifier<Offset>? tilt;
  final bool animate;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Desfasamos por carta para que no latan todas al mismo tiempo.
    final t = (animate ? time.value : 0.0) + (seed % 997) * 0.37;
    final tl = tilt?.value ?? Offset.zero;
    final rect = Offset.zero & size;

    // Sombra que se desplaza lentamente (luz de vela / nubes).
    final c = Offset(
      size.width * (0.5 + 0.28 * math.sin(t * 0.31) + tl.dx * 0.3),
      size.height * (0.42 + 0.22 * math.cos(t * 0.23) + tl.dy * 0.3),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(c, size.longestSide * 0.85, [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.18),
          Colors.black.withValues(alpha: 0.62),
        ], [0.25, 0.65, 1]),
    );

    // Luz de borde con el color de la rareza.
    final rim = rarityGlowColor(rarity, t);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height),
          Offset(0, size.height * 0.55),
          [rim.withValues(alpha: 0.12 + 0.35 * rarity.glow), rim.withValues(alpha: 0)],
        ),
    );

    // Holograma para legendarias, míticas y el marco holográfico.
    if (rarity.index >= Rarity.legendary.index || frame.fx == FrameFx.holo || tl != Offset.zero) {
      final shift = (t * 0.08 + tl.dx * 0.5 + tl.dy * 0.3) % 1.0;
      final a = (frame.fx == FrameFx.holo ? 0.3 : 0.16) + tl.distance * 0.2;
      final colors = [
        for (final h in [0, 50, 110, 180, 240, 300, 360])
          HSVColor.fromAHSV(a.clamp(0, 0.6), (h + shift * 360) % 360, 0.6, 1).toColor(),
      ];
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.overlay
          ..shader = ui.Gradient.linear(
            Offset(size.width * (-0.5 + shift), 0),
            Offset(size.width * (0.5 + shift), size.height),
            colors,
            [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)],
            TileMode.mirror,
          ),
      );
    }

    // Reflejo que cruza la carta cada tanto (o sigue al dedo / la inclinación).
    double? phase;
    if (tl != Offset.zero) {
      phase = 0.5 + tl.dx * 0.8;
    } else if (rarity.shineEvery > 0) {
      final local = t % rarity.shineEvery;
      if (local < 1.1) phase = local / 1.1;
    }
    if (phase != null) {
      final x = -size.width * 0.6 + phase * size.width * 2.2;
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.linear(
            Offset(x - 50, 0),
            Offset(x + 50, size.height * 0.5),
            [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.42), Colors.white.withValues(alpha: 0)],
            [0, 0.5, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(ShadePainter old) =>
      old.rarity != rarity || old.frame != frame || old.animate != animate || old.seed != seed;
}

// ---------------------------------------------------------------------------
// Matasellos
// ---------------------------------------------------------------------------

class PostmarkPainter extends CustomPainter {
  PostmarkPainter({required this.date, required this.number, required this.ink, required this.detail});

  final String date;
  final String number;
  final Color ink;

  /// 0..1: cuánto detalle se ve (el texto aparece al acercarse).
  final double detail;

  @override
  void paint(Canvas canvas, Size size) {
    final color = ink.withValues(alpha: 0.5);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = color;
    const c = Offset(kCardW - 60, kCardH - 88);
    const r = 30.0;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.22);
    canvas.drawCircle(Offset.zero, r, p);
    canvas.drawCircle(Offset.zero, r - 4, p..strokeWidth = 0.7);
    // Líneas onduladas de cancelación.
    for (var i = -1; i <= 1; i++) {
      final path = Path()..moveTo(-r - 62, i * 8.0);
      for (var x = -r - 62; x < -r - 2; x += 2) {
        path.lineTo(x, i * 8.0 + math.sin(x * 0.35) * 2.2);
      }
      canvas.drawPath(path, p..strokeWidth = 1.2);
    }
    if (detail > 0.01) {
      void text(String s, double y, double sz) {
        final tp = TextPainter(
          text: TextSpan(
            text: s,
            style: TextStyle(
              fontFamily: kTitleFont,
              fontSize: sz,
              color: color.withValues(alpha: color.a * detail),
              letterSpacing: 0.6,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(-tp.width / 2, y - tp.height / 2));
      }

      text('ÍDOLOS', -15, 5.5);
      text(date, 0, 6.4);
      text(number, 14, 5.5);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PostmarkPainter old) =>
      old.date != date || old.ink != ink || old.detail != detail || old.number != number;
}
