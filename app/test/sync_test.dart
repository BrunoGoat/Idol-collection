import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idol_collection/data/collection.dart';
import 'package:idol_collection/data/settings.dart';
import 'package:idol_collection/models/idol.dart';
import 'package:idol_collection/models/layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_github.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeGitHub gh;
  late AppSettings settings;

  Future<Collection> open() => Collection.open(settings, baseDir: tmp, httpFactory: gh.client);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('idols');
    gh = FakeGitHub()..seedFromDisk('../collection', 'collection');
    settings = AppSettings();
    await settings.load();
    settings
      ..token = 'test-token'
      ..owner = 'BrunoGoat'
      ..repo = 'Idol-collection'
      ..branch = 'main';
  });

  tearDown(() async {
    // Puede quedar alguna miniatura generándose en segundo plano.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // No importa: es un directorio temporal.
    }
  });

  test('primera sincronización: baja todo y no marca novedades', () async {
    final c = await open();
    expect(c.idols, isEmpty);
    await c.sync();
    expect(c.status, SyncStatus.ok, reason: c.lastError);
    expect(c.idols.length, 8);
    expect(c.layout.cards.length, 8);
    expect(c.arrivals, isEmpty);
    expect(c.numbers['marie-curie'], 1);
    expect(c.pendingCount, 0);
    expect(gh.commits, 0, reason: 'sin cambios locales no se sube nada');

    // Una segunda sincronización no vuelve a descargar nada.
    final before = gh.blobDownloads;
    await c.sync();
    expect(gh.blobDownloads, before);
  });

  test('un ídolo agregado en el repo aparece como novedad y se ubica solo', () async {
    final c = await open();
    await c.sync();
    gh.put('collection/idols/nuevo/card.md', '---\nname: Nuevo Ídolo\nrarity: legendaria\n---\n\nHola');
    gh.files['collection/idols/nuevo/image.jpg'] = gh.files['collection/idols/marie-curie/image.jpg']!;
    await c.sync();
    expect(c.idols['nuevo']!.name, 'Nuevo Ídolo');
    expect(c.arrivals, ['nuevo']);
    expect(c.layout.cards['nuevo'], isNotNull);
    // La posición autoasignada se sube al repo para que sea estable.
    await c.sync();
    final remote = BoardLayout.fromJsonString(gh.text('collection/layout.json'));
    expect(remote.cards['nuevo'], isNotNull);
  });

  test('mover una carta sube solo esa posición y respeta cambios remotos', () async {
    final c = await open();
    await c.sync();
    c.layout.cards['marie-curie']!
      ..x = 1234
      ..scale = 2;
    await c.commitPlacement('marie-curie');

    // Mientras tanto, alguien (Claude) movió a Tesla en el repo.
    final remote = BoardLayout.fromJsonString(gh.text('collection/layout.json'));
    remote.cards['nikola-tesla']!.x = -999;
    gh.put('collection/layout.json', remote.toJsonString());

    await c.sync();
    expect(c.status, SyncStatus.ok, reason: c.lastError);
    expect(gh.commits, 1);
    final after = BoardLayout.fromJsonString(gh.text('collection/layout.json'));
    expect(after.cards['marie-curie']!.x, 1234);
    expect(after.cards['marie-curie']!.scale, 2);
    expect(after.cards['nikola-tesla']!.x, -999, reason: 'no hay que pisar el cambio remoto');
    expect(c.layout.cards['nikola-tesla']!.x, -999);
    expect(c.pendingCount, 0);
  });

  test('agregar, editar y quitar un ídolo desde la app', () async {
    final c = await open();
    await c.sync();
    final jpg = File('../collection/idols/jesse-owens/image.jpg').readAsBytesSync();
    final idol = await c.addIdol(
      Idol(id: 'x', name: 'Ada Nueva', category: 'Ciencia', body: 'Porque sí.'),
      jpg,
    );
    await c.sync();
    expect(idol.id, 'ada-nueva');
    expect(c.numbers['ada-nueva'], 9);
    expect(gh.files.containsKey('collection/idols/ada-nueva/image.jpg'), isTrue);
    final md = gh.text('collection/idols/ada-nueva/card.md')!;
    expect(md, contains('name: "Ada Nueva"'));
    expect(BoardLayout.fromJsonString(gh.text('collection/layout.json')).cards['ada-nueva'], isNotNull);
    expect(c.arrivals, isEmpty, reason: 'lo que agrego yo no se revela como sorpresa');

    // Lo subido no se vuelve a descargar.
    final downloads = gh.blobDownloads;
    await c.sync();
    expect(gh.blobDownloads, downloads);

    final edited = c.idols['ada-nueva']!.copy()..title = 'Pionera';
    await c.updateIdol(edited);
    await c.sync();
    expect(gh.text('collection/idols/ada-nueva/card.md'), contains('title: "Pionera"'));

    await c.deleteIdol('ada-nueva');
    await c.sync();
    expect(c.status, SyncStatus.ok, reason: c.lastError);
    expect(gh.files.keys.where((k) => k.contains('ada-nueva')), isEmpty);
    expect(BoardLayout.fromJsonString(gh.text('collection/layout.json')).cards.containsKey('ada-nueva'), isFalse);
    expect(c.idols.containsKey('ada-nueva'), isFalse);
  });

  test('sin conexión trabaja local y sube después', () async {
    final c = await open();
    await c.sync();
    settings.token = '';
    c.layout.cards['jesse-owens']!.x = 42;
    await c.commitPlacement('jesse-owens');
    await c.sync();
    expect(c.status, SyncStatus.notConfigured);
    expect(c.pendingCount, greaterThan(0));

    // Reabrir la app conserva el cambio pendiente.
    settings.token = 'test-token';
    final reopened = await open();
    expect(reopened.layout.cards['jesse-owens']!.x, 42);
    await reopened.sync();
    expect(reopened.pendingCount, 0);
    expect(jsonDecode(gh.text('collection/layout.json')!)['cards']['jesse-owens']['x'], 42);
  });

  test('cambiar el fondo se guarda en el repo', () async {
    final c = await open();
    await c.sync();
    await c.setTheme('synthwave');
    await c.sync();
    expect(BoardLayout.fromJsonString(gh.text('collection/layout.json')).theme, 'synthwave');
  });

  test('una rama sin collection/ da un error claro', () async {
    gh.files.clear();
    gh.put('README.md', 'hola');
    final c = await open();
    await c.sync();
    expect(c.status, SyncStatus.error);
    expect(c.lastError, contains('no tiene la carpeta collection/'));
  });
}
