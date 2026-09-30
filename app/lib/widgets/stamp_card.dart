import 'package:flutter/material.dart';

import '../models/catalog.dart';
import '../models/idol.dart';
import 'stamp_painters.dart';

/// Una carta-estampilla. Siempre se dibuja a tamaño base (240×320); quien la usa
/// la escala con un Transform o FittedBox.
class StampCard extends StatelessWidget {
  const StampCard({
    super.key,
    required this.idol,
    required this.number,
    required this.image,
    required this.time,
    this.textOpacity = 1,
    this.detail = 1,
    this.animate = true,
    this.selected = false,
    this.tilt,
    this.glowBoost = 1,
  });

  final Idol idol;
  final int number;
  final ImageProvider? image;
  final ValueNotifier<double> time;

  /// Opacidad del nombre (aparece al acercarse).
  final double textOpacity;

  /// Opacidad de los detalles finos (título, número, matasellos).
  final double detail;
  final bool animate;
  final bool selected;
  final ValueNotifier<Offset>? tilt;
  final double glowBoost;

  @override
  Widget build(BuildContext context) {
    final frame = idol.frameStyle;
    final font = idol.fontOption;
    final numberText = 'Nº ${number.toString().padLeft(3, '0')}';
    return SizedBox(
      width: kCardW,
      height: kCardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: GlowPainter(
                  rarity: idol.rarity,
                  time: animate ? time : _still,
                  selected: selected,
                  boost: glowBoost,
                ),
              ),
            ),
          ),
          ClipPath(
            clipper: const StampClipper(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: PaperPainter(frame: frame, time: time, animate: animate)),
                  ),
                ),
                Positioned.fromRect(
                  rect: kWindow,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Picture(image: image, idol: idol),
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: ShadePainter(
                              rarity: idol.rarity,
                              frame: frame,
                              time: time,
                              animate: animate,
                              tilt: tilt,
                              seed: idol.id.hashCode,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (detail > 0.01) ...[
                  Positioned(
                    left: kWindow.left + 6,
                    top: kWindow.top + 6,
                    child: Opacity(opacity: detail, child: _Plate(text: numberText, frame: frame)),
                  ),
                  Positioned(
                    right: kWindow.left + 6,
                    top: kWindow.top + 6,
                    child: Opacity(opacity: detail, child: _Stars(rarity: idol.rarity)),
                  ),
                ],
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: PostmarkPainter(
                        date: postmarkDate(idol.added),
                        number: numberText,
                        ink: frame.isDark ? frame.ink : frame.border,
                        detail: detail,
                      ),
                    ),
                  ),
                ),
                if (textOpacity > 0.01)
                  Positioned.fromRect(
                    rect: kBand,
                    child: Opacity(
                      opacity: textOpacity,
                      child: _NameBand(idol: idol, font: font, frame: frame, detail: detail),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static final _still = ValueNotifier<double>(0);
}

class _Picture extends StatelessWidget {
  const _Picture({required this.image, required this.idol});
  final ImageProvider? image;
  final Idol idol;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [idol.rarity.color.withValues(alpha: 0.9), Colors.black],
        ),
      ),
      child: Center(
        child: Text(
          idol.name.isEmpty ? '?' : idol.name.characters.first.toUpperCase(),
          style: idol.fontOption.style(96, color: Colors.white.withValues(alpha: 0.85)),
        ),
      ),
    );
    if (image == null) return fallback;
    return Image(
      image: image!,
      fit: BoxFit.cover,
      alignment: Alignment(idol.focusX, idol.focusY),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: frame == null && !sync ? 0 : 1,
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
    );
  }
}

class _NameBand extends StatelessWidget {
  const _NameBand({required this.idol, required this.font, required this.frame, required this.detail});
  final Idol idol;
  final FontOption font;
  final FrameStyle frame;
  final double detail;

  @override
  Widget build(BuildContext context) {
    final glow = rarityGlowColor(idol.rarity, 0);
    final shadows = [
      Shadow(color: frame.isDark ? glow.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.8), blurRadius: 10),
      Shadow(color: Colors.black.withValues(alpha: frame.isDark ? 0.8 : 0.25), blurRadius: 2, offset: const Offset(0, 1)),
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 32,
          width: kBand.width - 16,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              font.apply(idol.name),
              maxLines: 1,
              style: font.style(24, color: frame.ink, shadows: shadows),
            ),
          ),
        ),
        if (idol.title != null && detail > 0.01)
          Opacity(
            opacity: detail,
            child: SizedBox(
              width: kBand.width - 20,
              child: Text(
                idol.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kBodyFont,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  color: frame.ink.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({required this.text, required this.frame});
  final String text;
  final FrameStyle frame;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: frame.border2.withValues(alpha: 0.7), width: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          text,
          style: const TextStyle(fontFamily: kTitleFont, fontSize: 8, color: Colors.white, letterSpacing: 1),
        ),
      );
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rarity});
  final Rarity rarity;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          '★' * rarity.stars,
          style: TextStyle(
            fontSize: 9,
            color: rarity.color,
            shadows: [Shadow(color: rarity.color, blurRadius: 4)],
          ),
        ),
      );
}
