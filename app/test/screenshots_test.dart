// Genera capturas de pantalla reales de la app para revisar el diseño.
// Se corre a mano:  SCREENSHOTS=1 flutter test test/screenshots_test.dart
// Las imágenes quedan en build/screenshots/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idol_collection/app_scope.dart';
import 'package:idol_collection/data/collection.dart';
import 'package:idol_collection/data/settings.dart';
import 'package:idol_collection/main.dart';
import 'package:idol_collection/models/catalog.dart';
import 'package:idol_collection/screens/catalog_screen.dart';
import 'package:idol_collection/screens/reveal_overlay.dart';
import 'package:idol_collection/services/sfx.dart';
import 'package:idol_collection/widgets/backgrounds.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_github.dart';

final _enabled = Platform.environment['SCREENSHOTS'] == '1';
final _out = Directory('build/screenshots');
final _rootKey = GlobalKey();

Future<void> _loadFonts() async {
  for (final f in [...kFonts.map((f) => f.id), 'CormorantGaramond']) {
    final loader = FontLoader(f)..addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f.ttf').readAsBytesSync())));
    await loader.load();
  }
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${_out.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _settleImages(WidgetTester tester) async {
  // Deja que se decodifiquen las imágenes (IO real) y pinta de nuevo.
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Collection collection;
  late AppSettings settings;

  setUpAll(() async {
    if (!_enabled) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    _out.createSync(recursive: true);
  });

  Future<void> boot(WidgetTester tester, {String theme = 'nebulosa'}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('shots');
      final gh = FakeGitHub()..seedFromDisk('test/fixtures/collection', 'collection');
      settings = AppSettings();
      await settings.load();
      settings
        ..token = 'x'
        ..sound = false
        ..haptics = false
        ..idolOfTheDay = false
        ..tiltHolo = false;
      if (Platform.environment['TUTORIAL'] != '1') await settings.setSeenTutorial();
      collection = await Collection.open(settings, basePath: tmp.path, httpFactory: gh.client);
      await collection.sync();
      if (theme != collection.layout.theme) collection.layout.theme = theme;
      settings.token = ''; // que el tablero no intente sincronizar dentro del test
      while (collection.thumbs.length < collection.idols.length) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpWidget(RepaintBoundary(key: _rootKey, child: IdolApp(settings: settings, collection: collection)));
    await tester.pump(const Duration(milliseconds: 100));
    await _settleImages(tester);
  }

  Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('tablero, detalle, reverso y edición', (tester) async {
    await boot(tester);
    await tester.pump(const Duration(seconds: 2));
    await _settleImages(tester);
    await _shot(tester, '01_tablero_lejos');

    // Acercarse a la zona de Ciencia.
    await wheel(tester, const Offset(110, 420), -420);
    await tester.pump(const Duration(milliseconds: 1400));
    await _settleImages(tester);
    await _shot(tester, '02_tablero_cerca');

    // Tocar a Marie Curie → vuela la cámara y se abre la carta.
    await tester.tap(find.text('Marie Curie').first, warnIfMissed: false);
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settleImages(tester);
    await tester.pump(const Duration(milliseconds: 700));
    await _shot(tester, '03_detalle_frente');

    // Darla vuelta.
    await tester.tapAt(const Offset(205, 380));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _shot(tester, '04_detalle_reverso');

    // Cerrar y entrar en modo edición con pulsación larga.
    await tester.tap(find.text('Cerrar'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final gesture = await tester.startGesture(const Offset(205, 440));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(40, -30));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '05_modo_edicion');
    await tester.tap(find.text('Listo'));
    await tester.pump(const Duration(seconds: 1));
  }, skip: !_enabled);

  testWidgets('revelación de carta nueva', (tester) async {
    await boot(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    final idol = collection.idols['jesse-owens']!;
    nav.push(RevealOverlay.route(idol, 8, ValueNotifier(1.0)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await _shot(tester, '06_revelacion_sobre');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settleImages(tester);
    await tester.pump(const Duration(milliseconds: 900));
    await _shot(tester, '07_revelacion_carta');
  }, skip: !_enabled);

  testWidgets('catálogo de marcos y fuentes', (tester) async {
    await boot(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const CatalogScreen(initialTab: 1)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _settleImages(tester);
    await _shot(tester, '08_marcos_1');
    await tester.drag(find.byType(GridView), const Offset(0, -900));
    await tester.pump(const Duration(seconds: 1));
    await _settleImages(tester);
    await _shot(tester, '09_marcos_2');
    await tester.drag(find.byType(GridView), const Offset(0, -900));
    await tester.pump(const Duration(seconds: 1));
    await _settleImages(tester);
    await _shot(tester, '10_marcos_3');
    nav.push(MaterialPageRoute<void>(builder: (_) => const CatalogScreen(initialTab: 2)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '11_fuentes_1');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -800));
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '12_fuentes_2');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -800));
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '13_fuentes_3');
  }, skip: !_enabled);

  testWidgets('los 20 fondos', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    final time = ValueNotifier<double>(3.7);
    final cam = ValueNotifier(const CameraView(Offset(120, 80), 1));
    await tester.pumpWidget(RepaintBoundary(
      key: _rootKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: GridView.count(
          crossAxisCount: 4,
          childAspectRatio: 400 / 480,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final t in kThemes)
              Stack(children: [
                Positioned.fill(child: BoardBackground(theme: t, time: time, camera: cam)),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Text(
                    t.name,
                    style: const TextStyle(fontFamily: kTitleFont, fontSize: 22, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                  ),
                ),
              ]),
          ],
        ),
      ),
    ));
    await tester.pump();
    await _shot(tester, '14_fondos');
  }, skip: !_enabled);

  testWidgets('tablero con otros fondos', (tester) async {
    for (final theme in ['synthwave', 'album', 'marmol']) {
      await boot(tester, theme: theme);
      await tester.pump(const Duration(seconds: 1));
      await _settleImages(tester);
      await _shot(tester, '15_tablero_$theme');
    }
  }, skip: !_enabled);

  test('placeholder para que el archivo no quede vacío sin SCREENSHOTS', () {
    expect(AppScope, isNotNull);
    expect(Sfx, isNotNull);
  });
}
