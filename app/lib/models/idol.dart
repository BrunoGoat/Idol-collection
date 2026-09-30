import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'catalog.dart';

/// Un ídolo: lo que vive en `collection/idols/<id>/card.md`.
class Idol {
  Idol({
    required this.id,
    required this.name,
    this.title,
    this.category,
    this.rarity = Rarity.rare,
    this.frame = 'clasico',
    this.font = 'Cinzel',
    DateTime? added,
    this.number,
    this.quote,
    this.image = 'image.jpg',
    this.focusX = 0,
    this.focusY = 0,
    this.body = '',
  }) : added = added ?? DateTime.now();

  /// Nombre de la carpeta (slug). Es el identificador estable de la carta.
  final String id;
  String name;
  String? title;
  String? category;
  Rarity rarity;
  String frame;
  String font;
  DateTime added;
  int? number;
  String? quote;

  /// Archivo de imagen dentro de la carpeta del ídolo.
  String image;

  /// Punto de encuadre de la imagen (-1..1), como `Alignment`.
  double focusX;
  double focusY;

  /// Por qué lo admiro (markdown).
  String body;

  String get folder => 'collection/idols/$id';
  String get mdPath => '$folder/card.md';
  String get imagePath => '$folder/$image';

  FrameStyle get frameStyle => frameById(frame);
  FontOption get fontOption => fontById(font);

  Idol copy() => Idol.fromMarkdown(id, toMarkdown());

  static Idol fromMarkdown(String id, String source) {
    var front = <String, dynamic>{};
    var body = source;
    final text = source.replaceAll('\r\n', '\n');
    if (text.startsWith('---')) {
      final end = text.indexOf('\n---', 3);
      if (end > 0) {
        final yamlText = text.substring(3, end);
        final parsed = loadYaml(yamlText);
        if (parsed is YamlMap) {
          front = Map<String, dynamic>.from(parsed.map((k, v) => MapEntry(k.toString(), v)));
        }
        final after = text.indexOf('\n', end + 4);
        body = after < 0 ? '' : text.substring(after + 1);
      }
    }
    final focus = front['focus'];
    return Idol(
      id: id,
      name: (front['name'] ?? id).toString(),
      title: _str(front['title']),
      category: _str(front['category']),
      rarity: RarityInfo.parse(front['rarity']),
      frame: _str(front['frame']) ?? 'clasico',
      font: _str(front['font']) ?? 'Cinzel',
      added: DateTime.tryParse(front['added']?.toString() ?? '') ?? DateTime(2026),
      number: front['number'] is int ? front['number'] as int : int.tryParse('${front['number']}'),
      quote: _str(front['quote']),
      image: _str(front['image']) ?? 'image.jpg',
      focusX: focus is List && focus.length == 2 ? (focus[0] as num).toDouble() : 0,
      focusY: focus is List && focus.length == 2 ? (focus[1] as num).toDouble() : 0,
      body: body.trim(),
    );
  }

  String toMarkdown() {
    final b = StringBuffer('---\n');
    void field(String key, Object? value) {
      if (value == null) return;
      if (value is String) {
        if (value.trim().isEmpty) return;
        b.writeln('$key: ${jsonEncode(value)}');
      } else {
        b.writeln('$key: $value');
      }
    }

    field('name', name);
    field('title', title);
    field('category', category);
    field('rarity', rarity.name);
    field('frame', frame);
    field('font', font);
    field('added', _date(added));
    field('number', number);
    field('quote', quote);
    field('image', image);
    if (focusX != 0 || focusY != 0) {
      b.writeln('focus: [${focusX.toStringAsFixed(2)}, ${focusY.toStringAsFixed(2)}]');
    }
    b.writeln('---');
    b.writeln();
    b.writeln(body.trim());
    return b.toString();
  }

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Convierte un nombre en un slug apto para carpeta: "Marie Curie" → "marie-curie".
String slugify(String input) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  var s = input.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    s = s.replaceAll(from[i], to[i]);
  }
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'idolo' : s;
}

const _months = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];

/// "30 SEP 2026" para el matasellos.
String postmarkDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
