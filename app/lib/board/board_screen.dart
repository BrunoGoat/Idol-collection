import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_scope.dart';
import '../data/collection.dart';
import '../data/settings.dart';
import '../models/catalog.dart';
import '../models/idol.dart';
import '../models/layout.dart';
import '../screens/card_editor_screen.dart';
import '../screens/detail_screen.dart';
import '../screens/reveal_overlay.dart';
import '../screens/search_sheet.dart';
import '../screens/settings_screen.dart';
import '../services/sfx.dart';
import '../widgets/backgrounds.dart';
import '../widgets/glass.dart';
import '../widgets/stamp_card.dart';
import '../widgets/stamp_painters.dart';
import 'board_layers.dart';
import 'camera.dart';

enum _Gesture { camera, moveCard, transformCard }

/// Nivel de detalle de una carta según cuán grande se ve en pantalla.
class _Lod {
  _Lod(double screenW)
      : text = _q(smoothstep(105, 165, screenW)),
        detail = _q(smoothstep(210, 290, screenW)),
        animate = screenW > 70,
        minimal = screenW < 42,
        thumb = screenW < 190,
        hires = screenW > 480;

  final double text;
  final double detail;
  final bool animate;
  final bool minimal;
  final bool thumb;
  final bool hires;

  static double _q(double v) => (v * 8).round() / 8;

  int get key => Object.hash(text, detail, animate, minimal, thumb, hires);
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final time = ValueNotifier<double>(0);
  final camera = ValueNotifier<CameraView>(const CameraView(Offset.zero, 0.7));
  late final Ticker _ticker;

  late Collection collection;
  late AppSettings settings;
  late Sfx sfx;
  bool _wired = false;

  Size _screen = Size.zero;
  int _visibleKey = 0;
  bool _fitted = false;
  bool _dailyDone = false;
  bool _revealing = false;

  String? _selected;
  String? _highlight;
  Timer? _highlightTimer;

  AnimationController? _anim;

  // Estado del gesto en curso.
  _Gesture _gesture = _Gesture.camera;
  CameraView _startCam = CameraView.zero;
  Offset _startFocal = Offset.zero;
  double _baseScale = 1;
  double _baseRotation = 0;
  Offset? _longPressLast;

  String? _banner;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => time.value = elapsed.inMicroseconds / 1e6)..start();
    camera.addListener(_onCamera);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final scope = AppScope.of(context);
    collection = scope.collection;
    settings = scope.settings;
    sfx = scope.sfx;
    collection.addListener(_onCollection);
    settings.addListener(_onCollection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onCollection();
      collection.sync();
    });
  }

  @override
  void dispose() {
    collection.removeListener(_onCollection);
    settings.removeListener(_onCollection);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _anim?.dispose();
    _bannerTimer?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) collection.sync();
  }

  // -------------------------------------------------------------------------
  // Reacciones a cambios
  // -------------------------------------------------------------------------

  void _onCollection() {
    if (!mounted) return;
    if (_selected != null && !collection.idols.containsKey(_selected)) _selected = null;
    if (!_fitted && collection.layout.cards.isNotEmpty && _screen != Size.zero) {
      _fitted = true;
      camera.value = _fitAll();
    }
    setState(() {});
    final syncDone = collection.status != SyncStatus.syncing && collection.status != SyncStatus.idle;
    if (syncDone) {
      if (collection.arrivals.isNotEmpty) {
        _dailyDone = true; // hoy manda la novedad
        _revealNext();
      } else {
        _maybeIdolOfTheDay();
      }
    }
  }

  void _onCamera() {
    final key = _computeVisibleKey();
    if (key != _visibleKey) setState(() => _visibleKey = key);
  }

  int _computeVisibleKey() {
    final cam = camera.value;
    return Object.hashAll([
      for (final e in _visibleEntries(cam)) Object.hash(e.key, _Lod(kCardW * e.value.scale * cam.zoom).key),
    ]);
  }

  List<MapEntry<String, Placement>> _visibleEntries(CameraView cam) {
    if (_screen == Size.zero) return const [];
    final view = visibleWorld(cam, _screen).inflate(120 / cam.zoom);
    final list = collection.layout.cards.entries
        .where((e) =>
            collection.idols.containsKey(e.key) &&
            view.overlaps(Rect.fromCircle(center: Offset(e.value.x, e.value.y), radius: e.value.radius)))
        .toList()
      ..sort((a, b) {
        if (a.key == _selected) return 1;
        if (b.key == _selected) return -1;
        return a.value.z.compareTo(b.value.z);
      });
    return list;
  }

  // -------------------------------------------------------------------------
  // Cámara
  // -------------------------------------------------------------------------

  CameraView _fitAll() {
    final cards = collection.layout.cards.values;
    if (cards.isEmpty || _screen == Size.zero) return const CameraView(Offset.zero, 0.7);
    var r = Rect.fromCircle(center: Offset(cards.first.x, cards.first.y), radius: cards.first.radius);
    for (final p in cards) {
      r = r.expandToInclude(Rect.fromCircle(center: Offset(p.x, p.y), radius: p.radius));
    }
    r = r.inflate(60);
    final zoom = math.min(_screen.width / r.width, (_screen.height - 160) / r.height).clamp(kMinZoom, 1.1);
    return CameraView(r.center, zoom);
  }

  CameraView _cardCamera(Placement p, {double fill = 0.62}) {
    final zoom = math.min(_screen.height * fill / (kCardH * p.scale), _screen.width * 0.86 / (kCardW * p.scale));
    return CameraView(Offset(p.x, p.y), zoom.clamp(kMinZoom, kMaxZoom));
  }

  void _stopAnim() {
    _anim?.stop();
    _anim?.dispose();
    _anim = null;
  }

  Future<void> _flyTo(CameraView target, {Duration duration = const Duration(milliseconds: 750)}) async {
    _stopAnim();
    final from = camera.value;
    final c = AnimationController(vsync: this, duration: duration);
    _anim = c;
    final curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    c.addListener(() => camera.value = flyLerp(from, target, curve.value, _screen));
    try {
      await c.forward().orCancel;
    } on TickerCanceled {
      // Otro gesto interrumpió el vuelo.
    }
  }

  void _fling(Velocity velocity) {
    final v = velocity.pixelsPerSecond;
    if (v.distance < 250) return;
    _stopAnim();
    final from = camera.value;
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _anim = c;
    final curve = CurvedAnimation(parent: c, curve: Curves.decelerate);
    final travel = -v * 0.32 / from.zoom;
    c.addListener(() => camera.value = CameraView(from.center + travel * curve.value, from.zoom));
    c.forward();
  }

  void _jumpTo(Offset world, {bool animate = false}) {
    final target = CameraView(world, camera.value.zoom);
    if (animate) {
      _flyTo(target, duration: const Duration(milliseconds: 450));
    } else {
      _stopAnim();
      camera.value = target;
    }
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final cam = camera.value;
    final factor = math.exp(-e.scrollDelta.dy / 400);
    final zoom = (cam.zoom * factor).clamp(kMinZoom, kMaxZoom);
    final anchor = screenToWorld(e.localPosition, cam, _screen);
    camera.value = CameraView(anchor - (e.localPosition - _screen.center(Offset.zero)) / zoom, zoom);
  }

  // -------------------------------------------------------------------------
  // Gestos del tablero
  // -------------------------------------------------------------------------

  void _onScaleStart(ScaleStartDetails d) {
    _stopAnim();
    _startCam = camera.value;
    _startFocal = d.localFocalPoint;
    _gesture = _Gesture.camera;
    final p = _selected == null ? null : collection.layout.cards[_selected];
    if (p != null) {
      final w = screenToWorld(d.localFocalPoint, camera.value, _screen);
      if (d.pointerCount >= 2) {
        _gesture = _Gesture.transformCard;
        _baseScale = p.scale;
        _baseRotation = p.rotation;
      } else if (p.contains(w.dx, w.dy)) {
        _gesture = _Gesture.moveCard;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final p = _selected == null ? null : collection.layout.cards[_selected];
    if (p != null && d.pointerCount >= 2 && _gesture != _Gesture.transformCard) {
      _gesture = _Gesture.transformCard;
      _baseScale = p.scale / d.scale;
      _baseRotation = p.rotation - d.rotation;
    }
    final zoom = camera.value.zoom;
    switch (_gesture) {
      case _Gesture.camera:
        final z = (_startCam.zoom * d.scale).clamp(kMinZoom, kMaxZoom);
        final anchor = screenToWorld(_startFocal, _startCam, _screen);
        camera.value = CameraView(anchor - (d.localFocalPoint - _screen.center(Offset.zero)) / z, z);
      case _Gesture.moveCard:
        if (p == null) return;
        setState(() {
          p.x = (p.x + d.focalPointDelta.dx / zoom).clamp(-kWorldHalf + 500, kWorldHalf - 500);
          p.y = (p.y + d.focalPointDelta.dy / zoom).clamp(-kWorldHalf + 500, kWorldHalf - 500);
        });
      case _Gesture.transformCard:
        if (p == null) return;
        setState(() {
          p.scale = (_baseScale * d.scale).clamp(0.3, 6.0);
          p.rotation = _baseRotation + d.rotation;
          p.x += d.focalPointDelta.dx / zoom;
          p.y += d.focalPointDelta.dy / zoom;
        });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_gesture == _Gesture.camera) {
      _fling(d.velocity);
    } else if (_selected != null) {
      collection.commitPlacement(_selected!);
    }
  }

  void _onTapEmpty(TapUpDetails d) {
    if (_selected != null) {
      sfx.play(Sound.drop, volume: 0.4);
      setState(() => _selected = null);
    }
  }

  // -------------------------------------------------------------------------
  // Gestos sobre cartas
  // -------------------------------------------------------------------------

  void _onCardTap(String id) {
    if (_selected != null) {
      sfx.light();
      setState(() => _selected = id);
      return;
    }
    _openCard(id);
  }

  void _onCardLongPressStart(String id, LongPressStartDetails d) {
    _stopAnim();
    sfx.medium();
    sfx.play(Sound.pick);
    _longPressLast = d.globalPosition;
    final p = collection.layout.cards[id];
    if (p != null && p.z < collection.layout.maxZ) p.z = collection.layout.maxZ + 1;
    setState(() => _selected = id);
  }

  void _onCardLongPressMove(String id, LongPressMoveUpdateDetails d) {
    final p = collection.layout.cards[id];
    final last = _longPressLast;
    if (p == null || last == null) return;
    final delta = (d.globalPosition - last) / camera.value.zoom;
    _longPressLast = d.globalPosition;
    setState(() {
      p.x += delta.dx;
      p.y += delta.dy;
    });
  }

  void _onCardLongPressEnd(String id) {
    _longPressLast = null;
    sfx.light();
    sfx.play(Sound.drop);
    collection.commitPlacement(id);
  }

  // -------------------------------------------------------------------------
  // Acciones
  // -------------------------------------------------------------------------

  Future<void> _openCard(String id) async {
    final p = collection.layout.cards[id];
    if (p == null) return;
    sfx.play(Sound.whoosh, volume: 0.5);
    sfx.light();
    await _flyTo(_cardCamera(p), duration: const Duration(milliseconds: 650));
    if (!mounted) return;
    await Navigator.of(context).push(DetailScreen.route(id, time));
    if (mounted) setState(() {});
  }

  Future<void> _addCard() async {
    sfx.play(Sound.tap);
    final result = await Navigator.of(context).push<EditorResult>(
      MaterialPageRoute(builder: (_) => const CardEditorScreen()),
    );
    if (result == null || result.image == null || !mounted) return;
    final idol = await collection.addIdol(result.idol, result.image!, near: camera.value.center);
    if (!mounted) return;
    sfx.play(Sound.reveal);
    sfx.heavy();
    _flashHighlight(idol.id);
    final p = collection.layout.cards[idol.id];
    if (p != null) await _flyTo(_cardCamera(p, fill: 0.5), duration: const Duration(milliseconds: 1000));
  }

  Future<void> _editSelected() async {
    final idol = collection.idols[_selected];
    if (idol == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CardEditorScreen(existing: idol)));
    if (mounted) setState(() {});
  }

  void _flashHighlight(String id) {
    _highlightTimer?.cancel();
    setState(() => _highlight = id);
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  void _showBanner(String text) {
    _bannerTimer?.cancel();
    setState(() => _banner = text);
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  Future<void> _revealNext() async {
    if (_revealing || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final id = collection.takeArrival();
    final idol = id == null ? null : collection.idols[id];
    if (idol == null) return;
    _revealing = true;
    await Navigator.of(context).push(RevealOverlay.route(idol, collection.numbers[id] ?? 0, time));
    final p = collection.layout.cards[id];
    if (mounted && p != null) {
      _flashHighlight(id!);
      await _flyTo(_cardCamera(p, fill: 0.5), duration: const Duration(milliseconds: 900));
    }
    _revealing = false;
    if (mounted && collection.arrivals.isNotEmpty) _revealNext();
  }

  Future<void> _maybeIdolOfTheDay() async {
    if (_dailyDone || !settings.idolOfTheDay || collection.idols.length < 2) return;
    _dailyDone = true;
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (settings.lastIdolOfDay == today) return;
    await settings.setLastIdolOfDay(today);
    final all = collection.sortedIdols;
    final idol = all[(now.year * 372 + now.month * 31 + now.day) % all.length];
    final p = collection.layout.cards[idol.id];
    if (p == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    sfx.play(Sound.shimmer);
    _showBanner('✦ Ídolo del día ✦\n${idol.name}');
    _flashHighlight(idol.id);
    await _flyTo(_cardCamera(p, fill: 0.55), duration: const Duration(milliseconds: 1400));
  }

  Future<void> _openSearch() async {
    final id = await showSearchSheet(context);
    if (id == null || !mounted) return;
    final p = collection.layout.cards[id];
    if (p == null) return;
    sfx.play(Sound.whoosh, volume: 0.5);
    _flashHighlight(id);
    await _flyTo(_cardCamera(p, fill: 0.55), duration: const Duration(milliseconds: 1100));
  }

  void _onSyncTap() {
    switch (collection.status) {
      case SyncStatus.notConfigured:
        _openSettings();
      case SyncStatus.error:
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('No se pudo sincronizar'),
            content: Text(collection.lastError ?? 'Error desconocido'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openSettings();
                },
                child: const Text('Ajustes'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  collection.sync();
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        );
      default:
        collection.sync();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Construcción
  // -------------------------------------------------------------------------

  ImageProvider? _imageFor(Idol idol, _Lod lod) {
    final thumb = collection.thumbs[idol.id];
    if (lod.thumb && thumb != null) return FileImage(thumb);
    return ResizeImage(FileImage(collection.imageFile(idol)), width: lod.hires ? 1000 : 520, allowUpscaling: false);
  }

  Widget _card(String id, Placement p, CameraView cam) {
    final idol = collection.idols[id]!;
    final lod = _Lod(kCardW * p.scale * cam.zoom);
    return Positioned(
      key: ValueKey(id),
      left: p.x + kWorldHalf - kCardW / 2,
      top: p.y + kWorldHalf - kCardH / 2,
      width: kCardW,
      height: kCardH,
      child: Transform.rotate(
        angle: p.rotation,
        child: Transform.scale(
          scale: p.scale,
          child: GestureDetector(
            onTap: () => _onCardTap(id),
            onLongPressStart: (d) => _onCardLongPressStart(id, d),
            onLongPressMoveUpdate: (d) => _onCardLongPressMove(id, d),
            onLongPressEnd: (_) => _onCardLongPressEnd(id),
            child: lod.minimal
                ? _MiniCard(idol: idol, image: _imageFor(idol, lod), selected: _selected == id)
                : StampCard(
                    idol: idol,
                    number: collection.numbers[id] ?? 0,
                    image: _imageFor(idol, lod),
                    time: time,
                    textOpacity: lod.text,
                    detail: lod.detail,
                    animate: lod.animate || _selected == id || _highlight == id,
                    selected: _selected == id,
                    glowBoost: _highlight == id ? 2.2 : 1,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _cardsLayer() {
    final cam = camera.value;
    final cards = [for (final e in _visibleEntries(cam)) _card(e.key, e.value, cam)];
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: AnimatedBuilder(
        animation: camera,
        builder: (context, child) {
          final c = camera.value;
          return Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_screen.width / 2, _screen.height / 2, 0, 1)
              ..scaleByDouble(c.zoom, c.zoom, 1, 1)
              ..translateByDouble(-c.center.dx - kWorldHalf, -c.center.dy - kWorldHalf, 0, 1),
            child: child,
          );
        },
        child: SizedBox(
          width: kWorldSize,
          height: kWorldSize,
          child: Stack(clipBehavior: Clip.none, children: cards),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = themeById(collection.layout.theme);
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, constraints) {
        final first = _screen == Size.zero;
        _screen = constraints.biggest;
        if (first && !_fitted && collection.layout.cards.isNotEmpty) {
          _fitted = true;
          // No se puede mover la cámara en medio de un build: lo hacemos al terminar el frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) camera.value = _fitAll();
          });
        }
        final padding = MediaQuery.paddingOf(context);
        return Stack(
          children: [
            Positioned.fill(child: BoardBackground(theme: theme, time: time, camera: camera)),
            if (settings.constellations)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ConstellationPainter(
                      idols: collection.idols,
                      layout: collection.layout,
                      camera: camera,
                      time: time,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Listener(
                onPointerSignal: _onWheel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapEmpty,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: ClipRect(child: _cardsLayer()),
                ),
              ),
            ),
            if (collection.idols.isEmpty) _EmptyState(onAdd: _addCard, onSettings: _openSettings, configured: settings.isConfigured),
            Positioned(
              top: padding.top + 10,
              left: 12,
              right: 12,
              child: _TopBar(
                count: collection.idols.length,
                accent: theme.accent,
                status: collection.status,
                pending: collection.pendingCount,
                onSearch: _openSearch,
                onSync: _onSyncTap,
                onSettings: _openSettings,
                onFit: () => _flyTo(_fitAll(), duration: const Duration(milliseconds: 900)),
              ),
            ),
            if (_banner != null)
              Positioned(
                top: padding.top + 80,
                left: 0,
                right: 0,
                child: IgnorePointer(child: Center(child: _Banner(text: _banner!, accent: theme.accent))),
              ),
            if (collection.idols.isNotEmpty && _selected == null)
              Positioned(
                left: 14,
                bottom: padding.bottom + 16,
                child: Minimap(
                  idols: collection.idols,
                  layout: collection.layout,
                  camera: camera,
                  screen: _screen,
                  onJump: _jumpTo,
                ),
              ),
            if (_selected == null)
              Positioned(
                right: 18,
                bottom: padding.bottom + 22,
                child: _AddButton(time: time, accent: theme.accent, onTap: _addCard),
              ),
            if (_selected != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: padding.bottom + 16,
                child: _EditToolbar(
                  onFront: () {
                    sfx.light();
                    collection.bringToFront(_selected!);
                  },
                  onStraighten: () {
                    final p = collection.layout.cards[_selected]!;
                    setState(() => p.rotation = 0);
                    collection.commitPlacement(_selected!);
                  },
                  onSmaller: () => _resizeSelected(1 / 1.15),
                  onBigger: () => _resizeSelected(1.15),
                  onEdit: _editSelected,
                  onDone: () {
                    sfx.play(Sound.drop, volume: 0.4);
                    setState(() => _selected = null);
                  },
                ),
              ),
          ],
        );
      }),
    );
  }

  void _resizeSelected(double factor) {
    final p = collection.layout.cards[_selected];
    if (p == null) return;
    sfx.light();
    setState(() => p.scale = (p.scale * factor).clamp(0.3, 6.0));
    collection.commitPlacement(_selected!);
  }
}

/// Versión liviana de la carta para cuando se ve diminuta (cientos en pantalla).
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.idol, required this.image, required this.selected});
  final Idol idol;
  final ImageProvider? image;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final frame = idol.frameStyle;
    return ClipPath(
      clipper: const StampClipper(),
      child: Container(
        width: kCardW,
        height: kCardH,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: frame.paper.length > 1 ? frame.paper : [frame.paper.first, frame.paper.first]),
          border: selected ? Border.all(color: Colors.white, width: 8) : null,
        ),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 78),
        child: Container(
          decoration: BoxDecoration(
            color: idol.rarity.color,
            border: Border.all(color: idol.rarity.color, width: 6),
            image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover, alignment: Alignment(idol.focusX, idol.focusY)),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.count,
    required this.accent,
    required this.status,
    required this.pending,
    required this.onSearch,
    required this.onSync,
    required this.onSettings,
    required this.onFit,
  });

  final int count;
  final Color accent;
  final SyncStatus status;
  final int pending;
  final VoidCallback onSearch, onSync, onSettings, onFit;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String tip) = switch (status) {
      SyncStatus.syncing => (Icons.sync, 'Sincronizando…'),
      SyncStatus.ok => (Icons.cloud_done_outlined, 'Al día con el repo'),
      SyncStatus.offline => (Icons.cloud_off, 'Sin conexión: trabajando local'),
      SyncStatus.error => (Icons.error_outline, 'Error de sincronización'),
      SyncStatus.notConfigured => (Icons.link_off, 'Conectar con GitHub'),
      SyncStatus.idle => (Icons.cloud_outlined, 'Sincronizar'),
    };
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onFit,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'SALÓN DE ÍDOLOS',
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: 'CinzelDecorative',
                        fontSize: 16,
                        color: Colors.white,
                        letterSpacing: 1.5,
                        shadows: [Shadow(color: accent, blurRadius: 12)],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$count', style: TextStyle(fontFamily: kTitleFont, color: accent, fontSize: 14)),
                ],
              ),
            ),
          ),
          IconButton(onPressed: onSearch, icon: const Icon(Icons.search), color: Colors.white, tooltip: 'Buscar'),
          Badge(
            isLabelVisible: pending > 0,
            label: Text('$pending'),
            child: IconButton(
              onPressed: onSync,
              tooltip: tip,
              color: status == SyncStatus.error ? Colors.redAccent : Colors.white,
              icon: status == SyncStatus.syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(icon),
            ),
          ),
          IconButton(onPressed: onSettings, icon: const Icon(Icons.tune), color: Colors.white, tooltip: 'Ajustes'),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.time, required this.accent, required this.onTap});
  final ValueNotifier<double> time;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar ídolo',
      child: GestureDetector(
        onTap: onTap,
        child: ValueListenableBuilder<double>(
          valueListenable: time,
          builder: (context, t, _) {
            final pulse = 0.5 + 0.5 * math.sin(t * 2.2);
            return Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  transform: GradientRotation(t * 0.8),
                  colors: const [Color(0xFFFFE082), Color(0xFFFFB300), Color(0xFFFFF8E1), Color(0xFFFF8F00), Color(0xFFFFE082)],
                ),
                boxShadow: [
                  BoxShadow(color: accent.withValues(alpha: 0.35 + 0.35 * pulse), blurRadius: 18 + 14 * pulse, spreadRadius: 1 + 3 * pulse),
                  const BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: const Icon(Icons.add, size: 38, color: Color(0xFF3D2800)),
            );
          },
        ),
      ),
    );
  }
}

class _EditToolbar extends StatelessWidget {
  const _EditToolbar({
    required this.onFront,
    required this.onStraighten,
    required this.onSmaller,
    required this.onBigger,
    required this.onEdit,
    required this.onDone,
  });
  final VoidCallback onFront, onStraighten, onSmaller, onBigger, onEdit, onDone;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
          ),
        );
    return Glass(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              'Arrastrá para mover · pellizcá para escalar y rotar',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          Row(
            children: [
              btn(Icons.flip_to_front, 'Al frente', onFront),
              btn(Icons.straighten, 'Enderezar', onStraighten),
              btn(Icons.zoom_out, 'Achicar', onSmaller),
              btn(Icons.zoom_in, 'Agrandar', onBigger),
              btn(Icons.edit, 'Editar', onEdit),
              btn(Icons.check_circle, 'Listo', onDone),
            ],
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
      ),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'CinzelDecorative',
            fontSize: 18,
            color: Colors.white,
            height: 1.4,
            shadows: [Shadow(color: accent, blurRadius: 16)],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.onSettings, required this.configured});
  final VoidCallback onAdd, onSettings;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Glass(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tu salón está vacío',
                style: TextStyle(fontFamily: 'CinzelDecorative', fontSize: 22, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                configured
                    ? 'Tocá el + para agregar tu primer ídolo, o pedile a Claude que lo agregue al repo.'
                    : 'Conectá tu repo de GitHub para traer tu colección, o empezá agregando un ídolo con el +.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: kBodyFont, fontSize: 18, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (!configured)
                    OutlinedButton.icon(onPressed: onSettings, icon: const Icon(Icons.link), label: const Text('Conectar GitHub')),
                  FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Agregar ídolo')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
