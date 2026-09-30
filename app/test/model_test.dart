import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:idol_collection/models/catalog.dart';
import 'package:idol_collection/models/idol.dart';
import 'package:idol_collection/models/layout.dart';
import 'package:idol_collection/widgets/backgrounds.dart';

void main() {
  test('card.md: ida y vuelta sin perder datos', () {
    final idol = Idol(
      id: 'test',
      name: 'Ayrton "Magic" Senna',
      title: 'El Mago: de la lluvia',
      category: 'Deporte',
      rarity: Rarity.mythic,
      frame: 'fuego',
      font: 'PirataOne',
      added: DateTime(2026, 9, 30),
      number: 12,
      quote: 'Si ya no vas por un hueco que existe, dejás de ser un piloto.',
      focusX: 0.25,
      focusY: -0.5,
      body: 'Línea 1\n\n**Negrita** y _cursiva_.',
    );
    final back = Idol.fromMarkdown('test', idol.toMarkdown());
    expect(back.name, idol.name);
    expect(back.title, idol.title);
    expect(back.category, 'Deporte');
    expect(back.rarity, Rarity.mythic);
    expect(back.frame, 'fuego');
    expect(back.font, 'PirataOne');
    expect(back.added, DateTime(2026, 9, 30));
    expect(back.number, 12);
    expect(back.quote, idol.quote);
    expect(back.focusX, 0.25);
    expect(back.focusY, -0.5);
    expect(back.body, idol.body);
  });

  test('rarezas en español o inglés', () {
    expect(RarityInfo.parse('Legendaria'), Rarity.legendary);
    expect(RarityInfo.parse('mítica'), Rarity.mythic);
    expect(RarityInfo.parse('epic'), Rarity.epic);
    expect(RarityInfo.parse(null), Rarity.rare);
  });

  test('slugify', () {
    expect(slugify('Marie Curie'), 'marie-curie');
    expect(slugify('  Ñandú Ávila!! '), 'nandu-avila');
    expect(slugify('???'), 'idolo');
  });

  // La colección real (la tuya) y la de ejemplo que usan los tests.
  for (final root in ['../collection', 'test/fixtures/collection']) {
    test('las cartas de $root se leen bien', () {
      final dir = Directory('$root/idols');
      final ids = dir.existsSync()
          ? dir.listSync().whereType<Directory>().map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last).toList()
          : <String>[];
      for (final id in ids) {
        final idol = Idol.fromMarkdown(id, File('${dir.path}/$id/card.md').readAsStringSync());
        expect(idol.name, isNot(id), reason: '$id debería tener nombre');
        expect(kFrames.map((f) => f.id), contains(idol.frame), reason: '$id: marco desconocido');
        expect(kFonts.map((f) => f.id), contains(idol.font), reason: '$id: fuente desconocida');
        expect(File('${dir.path}/$id/${idol.image}').existsSync(), isTrue, reason: '$id: falta la imagen');
      }
      final layoutFile = File('$root/layout.json');
      if (layoutFile.existsSync()) {
        final layout = BoardLayout.fromJsonString(layoutFile.readAsStringSync());
        expect(ids.toSet().containsAll(layout.cards.keys), isTrue, reason: 'layout.json menciona cartas que no existen');
        expect(kThemes.map((t) => t.id), contains(layout.theme));
      }
    });
  }

  test('catálogo: 20 fondos, 12 marcos, 21 fuentes, sin ids repetidos', () {
    expect(kThemes.length, 20);
    expect(kFrames.length, 12);
    expect(kFonts.length, 21);
    expect(kThemes.map((t) => t.id).toSet().length, kThemes.length);
    expect(kFrames.map((t) => t.id).toSet().length, kFrames.length);
    expect(kFonts.map((t) => t.id).toSet().length, kFonts.length);
    for (final f in kFonts) {
      expect(File('assets/fonts/${f.id}.ttf').existsSync(), isTrue, reason: 'falta ${f.id}.ttf');
    }
  });

  test('layout: posición libre sin superponer y json ida y vuelta', () {
    final layout = BoardLayout(theme: 'aurora');
    for (var i = 0; i < 40; i++) {
      layout.cards['c$i'] = layout.findFreeSpot(seed: i);
    }
    final list = layout.cards.values.toList();
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final d = math.sqrt(math.pow(list[i].x - list[j].x, 2) + math.pow(list[i].y - list[j].y, 2));
        expect(d, greaterThan((list[i].radius + list[j].radius) * 0.7));
      }
    }
    final back = BoardLayout.fromJsonString(layout.toJsonString());
    expect(back.theme, 'aurora');
    expect(back.cards.length, 40);
    expect(back.cards['c3']!.x, closeTo(layout.cards['c3']!.x, 0.1));
  });

  test('Placement.contains respeta la rotación', () {
    final p = Placement(x: 0, y: 0, rotation: math.pi / 2);
    // Rotada 90°: ahora es más ancha que alta.
    expect(p.contains(kCardH / 2 - 5, 0), isTrue);
    expect(p.contains(0, kCardH / 2 - 5), isFalse);
  });
}
