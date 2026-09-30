import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/catalog.dart';
import '../models/idol.dart';
import '../services/sfx.dart';
import '../widgets/stamp_card.dart';
import '../widgets/stamp_painters.dart';

/// Animación de "¡carta nueva!": un sobre que tiembla, explota en luz y revela
/// la carta girando.
class RevealOverlay extends StatefulWidget {
  const RevealOverlay({super.key, required this.idol, required this.number, required this.time});

  final Idol idol;
  final int number;
  final ValueNotifier<double> time;

  static Route<void> route(Idol idol, int number, ValueNotifier<double> time) => PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => RevealOverlay(idol: idol, number: number, time: time),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  @override
  State<RevealOverlay> createState() => _RevealOverlayState();
}

class _RevealOverlayState extends State<RevealOverlay> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3600);
  static const _burstAt = 0.36; // fracción de la animación en que explota el sobre

  late final AnimationController _c = AnimationController(vsync: this, duration: _total);
  bool _burstPlayed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_burstPlayed && _c.value >= _burstAt) {
        _burstPlayed = true;
        final sfx = AppScope.of(context).sfx;
        sfx.play(Sound.reveal);
        sfx.heavy();
        if (widget.idol.rarity.index >= Rarity.legendary.index) {
          Future<void>.delayed(const Duration(milliseconds: 500), () => sfx.play(Sound.shimmer, volume: 0.5));
        }
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_c.value < _burstAt) {
      _c.value = _burstAt; // apurar la explosión
    } else if (_c.isAnimating) {
      _c.value = 1;
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = AppScope.of(context).collection;
    final idol = widget.idol;
    final color = idol.rarity.color;
    final screen = MediaQuery.sizeOf(context);
    final cardW = math.min(screen.width * 0.78, (screen.height - 220) * 0.75);
    final image = FileImage(collection.imageFile(idol));

    return GestureDetector(
      onTap: _onTap,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final pre = (v / _burstAt).clamp(0.0, 1.0); // sobre temblando
            final post = ((v - _burstAt) / (1 - _burstAt)).clamp(0.0, 1.0); // revelación
            final shake = pre * pre * 9;
            final flash = post > 0 ? (1 - Curves.easeOut.transform((post * 4).clamp(0.0, 1.0))) : 0.0;
            final cardIn = Curves.easeOutBack.transform((post * 1.8).clamp(0.0, 1.0));
            final spin = (1 - Curves.easeOutCubic.transform((post * 1.6).clamp(0.0, 1.0))) * math.pi * 4;
            final textIn = ((post - 0.45) / 0.3).clamp(0.0, 1.0);

            return Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // Rayos de luz girando detrás.
                Positioned.fill(
                  child: CustomPaint(painter: _RaysPainter(color: rarityGlowColor(idol.rarity, widget.time.value), t: v, strength: 0.4 + pre * 0.6)),
                ),
                if (post > 0) Positioned.fill(child: CustomPaint(painter: _BurstPainter(progress: post, color: color))),
                // El sobre.
                if (post == 0)
                  Center(child: Transform.translate(
                    offset: Offset(math.sin(v * 90) * shake, math.cos(v * 77) * shake * 0.5),
                    child: Transform.rotate(
                      angle: math.sin(v * 60) * 0.04 * pre,
                      child: Transform.scale(scale: 0.9 + pre * 0.15, child: _Pack(width: cardW * 0.8, color: color, t: v)),
                    ),
                  )),
                // La carta.
                if (post > 0)
                  Center(child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(spin)
                      ..scaleByDouble(0.2 + 0.8 * cardIn, 0.2 + 0.8 * cardIn, 1, 1),
                    child: SizedBox(
                      width: cardW,
                      height: cardW / 0.75,
                      child: FittedBox(
                        child: StampCard(
                          idol: idol,
                          number: widget.number,
                          image: image,
                          time: widget.time,
                          glowBoost: 1.8,
                        ),
                      ),
                    ),
                  )),
                // Textos.
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 40,
                  child: Opacity(
                    opacity: post == 0 ? pre : 1 - textIn * 0.3,
                    child: Text(
                      '¡NUEVA CARTA!',
                      style: TextStyle(
                        fontFamily: 'CinzelDecorative',
                        fontSize: 30,
                        color: Colors.white,
                        letterSpacing: 3,
                        shadows: [Shadow(color: color, blurRadius: 20)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: MediaQuery.paddingOf(context).bottom + 40,
                  child: Opacity(
                    opacity: textIn,
                    child: Column(
                      children: [
                        Text(
                          '${'★' * idol.rarity.stars}  ${idol.rarity.label.toUpperCase()}  ${'★' * idol.rarity.stars}',
                          style: TextStyle(fontFamily: kTitleFont, fontSize: 18, color: color, letterSpacing: 2, shadows: [Shadow(color: color, blurRadius: 14)]),
                        ),
                        const SizedBox(height: 14),
                        Text('Tocá para continuar', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ),
                if (flash > 0) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.white.withValues(alpha: flash)))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pack extends StatelessWidget {
  const _Pack({required this.width, required this.color, required this.t});
  final double width;
  final Color color;
  final double t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.45,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment(-1 + t * 4 % 2, -1),
          end: Alignment(1 + t * 4 % 2, 1),
          colors: [const Color(0xFF2B2B35), color, const Color(0xFFFFFFFF), color, const Color(0xFF2B2B35)],
          stops: const [0, 0.35, 0.5, 0.65, 1],
          tileMode: TileMode.mirror,
        ),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: 4)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(height: 10, margin: const EdgeInsets.symmetric(horizontal: 8), color: Colors.black26),
          const Spacer(),
          const Icon(Icons.auto_awesome, size: 64, color: Colors.white),
          const SizedBox(height: 10),
          const Text('ÍDOLOS', style: TextStyle(fontFamily: 'CinzelDecorative', fontSize: 28, color: Colors.white, letterSpacing: 4)),
          const Spacer(),
          Container(height: 10, margin: const EdgeInsets.symmetric(horizontal: 8), color: Colors.black26),
        ],
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter({required this.color, required this.t, required this.strength});
  final Color color;
  final double t;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.longestSide;
    for (var i = 0; i < 18; i++) {
      final a = i * math.pi * 2 / 18 + t * 2.5;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - 0.06) * r, c.dy + math.sin(a - 0.06) * r)
        ..lineTo(c.dx + math.cos(a + 0.06) * r, c.dy + math.sin(a + 0.06) * r)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(colors: [color.withValues(alpha: 0.35 * strength), color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r * 0.7)),
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => true;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rnd = math.Random(3);
    final e = Curves.easeOutCubic.transform(progress);
    for (var i = 0; i < 90; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final speed = 0.3 + rnd.nextDouble() * 0.7;
      final d = e * size.longestSide * 0.6 * speed;
      final p = c + Offset(math.cos(a), math.sin(a)) * d + Offset(0, e * e * 120 * speed);
      final alpha = (1 - progress).clamp(0.0, 1.0);
      final col = i.isEven ? color : Colors.white;
      canvas.drawCircle(
        p,
        1.5 + rnd.nextDouble() * 3,
        Paint()..color = col.withValues(alpha: alpha),
      );
    }
    final ring = Curves.easeOut.transform((progress * 2).clamp(0.0, 1.0));
    canvas.drawCircle(
      c,
      ring * size.shortestSide * 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - ring)
        ..color = color.withValues(alpha: 1 - ring),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}
