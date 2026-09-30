import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../board/board_layers.dart';
import '../models/catalog.dart';
import '../models/idol.dart';
import '../services/sfx.dart';
import '../widgets/stamp_card.dart';
import '../widgets/stamp_painters.dart';
import 'card_editor_screen.dart';

/// La carta de cerca: se da vuelta al tocarla, brilla con la inclinación del
/// teléfono y se puede compartir como imagen.
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.idolId, required this.time, this.backdrop});

  final String idolId;
  final ValueNotifier<double> time;

  /// Foto ya desenfocada del tablero. Con ella la ruta es opaca: el tablero
  /// deja de dibujarse (y de animarse) mientras la carta está abierta.
  final ui.Image? backdrop;

  static Route<void> route(String id, ValueNotifier<double> time, {ui.Image? backdrop}) => PageRouteBuilder<void>(
        opaque: backdrop != null,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => DetailScreen(idolId: id, time: time, backdrop: backdrop),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      );

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  final tilt = ValueNotifier<Offset>(Offset.zero);
  final _captureKey = GlobalKey();
  StreamSubscription<AccelerometerEvent>? _accel;
  Offset _sensorTilt = Offset.zero;
  bool _dragging = false;
  bool _sharing = false;
  Offset _settleFrom = Offset.zero;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      tilt.value = Offset.lerp(_settleFrom, _sensorTilt, Curves.easeOut.transform(_settle.value))!;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scope = AppScope.of(context);
      if (scope.settings.tiltHolo) _listenSensors();
      if (scope.collection.idols[widget.idolId]?.rarity.index case final r? when r >= Rarity.legendary.index) {
        scope.sfx.play(Sound.shimmer, volume: 0.4);
      }
    });
  }

  void _listenSensors() {
    try {
      _accel = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
        // Con el teléfono en la mano (~45°), x/y cerca de 0/7. Normalizamos a -1..1.
        final target = Offset((-e.x / 5).clamp(-1.0, 1.0), ((e.y - 6.5) / 5).clamp(-1.0, 1.0));
        _sensorTilt = Offset.lerp(_sensorTilt, target, 0.12)!;
        if (!_dragging) tilt.value = _sensorTilt;
      }, onError: (_) {});
    } catch (_) {
      // Sin acelerómetro (emulador): el holograma responde solo al dedo.
    }
  }

  @override
  void dispose() {
    _accel?.cancel();
    _flip.dispose();
    _settle.dispose();
    widget.backdrop?.dispose();
    tilt.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    AppScope.of(context).sfx
      ..play(Sound.flip)
      ..light();
    _flip.isCompleted || _flip.velocity > 0 ? _flip.reverse() : _flip.forward();
  }

  void _onPan(DragUpdateDetails d, Size cardSize) {
    _dragging = true;
    final local = d.localPosition;
    tilt.value = Offset(
      ((local.dx / cardSize.width) * 2 - 1).clamp(-1.0, 1.0),
      ((local.dy / cardSize.height) * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  void _onPanEnd() {
    _dragging = false;
    _settleFrom = tilt.value;
    _settle.forward(from: 0);
  }

  Future<void> _share(Idol idol) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      if (_flip.value > 0) await _flip.reverse();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final boundary = _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${idol.id}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: idol.name));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo compartir: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _delete(Idol idol) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Quitar a ${idol.name}?'),
        content: const Text('Se borra la carta y su imagen del repo. Queda en el historial de git por si te arrepentís.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).collection.deleteIdol(idol.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final collection = AppScope.of(context).collection;
    return ListenableBuilder(
      listenable: collection,
      builder: (context, _) {
        final idol = collection.idols[widget.idolId];
        if (idol == null) return const SizedBox.shrink();
        final number = collection.numbers[idol.id] ?? 0;
        final screen = MediaQuery.sizeOf(context);
        final cardW = math.min(screen.width * 0.86, (screen.height - 190) * 0.75);
        final cardSize = Size(cardW, cardW / 0.75);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.backdrop != null)
                        RawImage(image: widget.backdrop, fit: BoxFit.cover, filterQuality: FilterQuality.medium)
                      else
                        const ColoredBox(color: Colors.black),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(colors: [
                            rarityGlowColor(idol.rarity, 0).withValues(alpha: 0.22),
                            Colors.black.withValues(alpha: 0.82),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(),
                    Center(
                      child: GestureDetector(
                        onTap: _toggleFlip,
                        onPanUpdate: (d) => _onPan(d, cardSize),
                        onPanEnd: (_) => _onPanEnd(),
                        onPanCancel: _onPanEnd,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_flip, tilt]),
                          builder: (context, _) {
                            final v = Curves.easeInOutCubic.transform(_flip.value);
                            final showBack = v > 0.5;
                            final t = tilt.value;
                            final m = Matrix4.identity()
                              ..setEntry(3, 2, 0.0011)
                              ..rotateX(-t.dy * 0.22)
                              ..rotateY(t.dx * 0.28 + v * math.pi);
                            return Transform(
                              alignment: Alignment.center,
                              transform: m,
                              child: SizedBox.fromSize(
                                size: cardSize,
                                child: showBack
                                    ? Transform(
                                        alignment: Alignment.center,
                                        transform: Matrix4.rotationY(math.pi),
                                        child: _CardBack(idol: idol, number: number, size: cardSize),
                                      )
                                    : RepaintBoundary(
                                        key: _captureKey,
                                        child: FittedBox(
                                          child: Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: StampCard(
                                              idol: idol,
                                              number: number,
                                              image: ResizeImage(FileImage(collection.imageFile(idol)), width: 1400, allowUpscaling: false),
                                              time: widget.time,
                                              tilt: tilt,
                                              glowBoost: 1.3,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tocá la carta para darla vuelta · deslizá el dedo para verla brillar',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Row(
                        children: [
                          _Action(icon: Icons.flip, label: 'Voltear', onTap: _toggleFlip),
                          _Action(
                            icon: Icons.ios_share,
                            label: 'Compartir',
                            busy: _sharing,
                            onTap: () => _share(idol),
                          ),
                          _Action(
                            icon: Icons.edit,
                            label: 'Editar',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CardEditorScreen(existing: idol)),
                            ),
                          ),
                          _Action(icon: Icons.delete_outline, label: 'Quitar', onTap: () => _delete(idol)),
                          _Action(icon: Icons.close, label: 'Cerrar', onTap: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkResponse(
          onTap: busy ? null : onTap,
          radius: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(icon, color: Colors.white),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ),
      );
}

/// Reverso de la carta: nombre, rareza, frase y por qué lo admirás.
class _CardBack extends StatelessWidget {
  const _CardBack({required this.idol, required this.number, required this.size});
  final Idol idol;
  final int number;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final frame = idol.frameStyle;
    final font = idol.fontOption;
    final k = size.width / kCardW; // escala respecto de la carta base
    final ink = frame.ink;
    final glow = rarityGlowColor(idol.rarity, 0);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _BackGlowPainter(glow, idol.rarity.glow)),
        ),
        ClipPath(
          clipper: _ScaledStampClipper(k),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: frame.paper.length > 1 ? frame.paper : [frame.paper.first, frame.paper.first],
              ),
            ),
            padding: EdgeInsets.all(14 * k),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: frame.border, width: 1.4),
              ),
              padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      font.apply(idol.name),
                      style: font.style(30, color: ink, shadows: [Shadow(color: glow.withValues(alpha: 0.8), blurRadius: 14)]),
                    ),
                  ),
                  if (idol.title != null)
                    Text(
                      idol.title!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: kBodyFont, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, fontSize: 16, color: ink.withValues(alpha: 0.85)),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Chip(text: '${'★' * idol.rarity.stars}  ${idol.rarity.label.toUpperCase()}', color: idol.rarity.color),
                      if (idol.category != null) _Chip(text: idol.category!, color: categoryColor(idol.category!)),
                      _Chip(text: 'Nº ${number.toString().padLeft(3, '0')}', color: ink),
                    ],
                  ),
                  Divider(color: frame.border.withValues(alpha: 0.6), height: 18),
                  if (idol.quote != null) ...[
                    Text(
                      '“${idol.quote}”',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: kBodyFont, fontStyle: FontStyle.italic, fontSize: 17, color: ink, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: MarkdownBody(
                      data: idol.body.isEmpty ? '_Todavía no escribiste por qué lo admirás._' : idol.body,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(fontFamily: kBodyFont, fontSize: 16.5, color: ink, height: 1.25, fontWeight: FontWeight.w600),
                        strong: TextStyle(fontWeight: FontWeight.w900, color: ink),
                        em: TextStyle(fontStyle: FontStyle.italic, color: ink),
                        listBullet: TextStyle(color: ink),
                        h1: font.style(22, color: ink),
                        h2: font.style(19, color: ink),
                        h3: font.style(17, color: ink),
                      ),
                    ).wrapScroll(),
                  ),
                  Text(
                    'Se unió al salón el ${postmarkDate(idol.added)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: kTitleFont, fontSize: 10, letterSpacing: 1, color: ink.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension on Widget {
  Widget wrapScroll() => ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.9, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 16), child: this),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(fontFamily: kTitleFont, fontSize: 10, color: color, letterSpacing: 0.8)),
      );
}

class _ScaledStampClipper extends CustomClipper<Path> {
  const _ScaledStampClipper(this.k);
  final double k;
  @override
  Path getClip(Size size) => stampPath().transform((Matrix4.identity()..scaleByDouble(k, k, 1, 1)).storage);
  @override
  bool shouldReclip(_ScaledStampClipper old) => old.k != k;
}

class _BackGlowPainter extends CustomPainter {
  _BackGlowPainter(this.color, this.strength);
  final Color color;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / kCardW;
    canvas.scale(k);
    GlowImages.paint(canvas, GlowImages.glow, color.withValues(alpha: (0.9 * strength + 0.1).clamp(0.0, 1.0)));
  }

  @override
  bool shouldRepaint(_BackGlowPainter old) => old.color != color || old.strength != strength;
}
