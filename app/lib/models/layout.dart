import 'dart:convert';
import 'dart:math' as math;

import 'catalog.dart';

/// Dónde está una carta en el tablero. (x, y) es el centro en coordenadas del mundo.
class Placement {
  Placement({required this.x, required this.y, this.scale = 1, this.rotation = 0, this.z = 0});

  double x;
  double y;
  double scale;

  /// Radianes.
  double rotation;
  int z;

  factory Placement.fromJson(Map<String, dynamic> j) => Placement(
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        scale: (j['scale'] as num?)?.toDouble() ?? 1,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
        z: (j['z'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'x': _r(x),
        'y': _r(y),
        'scale': _r(scale, 3),
        'rotation': _r(rotation, 4),
        'z': z,
      };

  Placement copy() => Placement(x: x, y: y, scale: scale, rotation: rotation, z: z);

  double get width => kCardW * scale;
  double get height => kCardH * scale;

  /// Radio que contiene a la carta sin importar su rotación.
  double get radius => math.sqrt(width * width + height * height) / 2;

  /// ¿El punto del mundo cae dentro de la carta (teniendo en cuenta la rotación)?
  bool contains(double px, double py) {
    final dx = px - x, dy = py - y;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    final lx = dx * c - dy * s, ly = dx * s + dy * c;
    return lx.abs() <= width / 2 && ly.abs() <= height / 2;
  }

  static double _r(double v, [int digits = 1]) {
    final p = math.pow(10, digits);
    return (v * p).roundToDouble() / p;
  }
}

/// Contenido de `collection/layout.json`.
class BoardLayout {
  BoardLayout({this.theme = 'nebulosa', Map<String, Placement>? cards}) : cards = cards ?? {};

  String theme;
  final Map<String, Placement> cards;

  factory BoardLayout.fromJsonString(String? source) {
    if (source == null || source.trim().isEmpty) return BoardLayout();
    final j = jsonDecode(source) as Map<String, dynamic>;
    final board = (j['board'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cards = (j['cards'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BoardLayout(
      theme: board['theme']?.toString() ?? 'nebulosa',
      cards: cards.map((k, v) => MapEntry(k, Placement.fromJson((v as Map).cast<String, dynamic>()))),
    );
  }

  String toJsonString() {
    final ids = cards.keys.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'board': {'theme': theme},
      'cards': {for (final id in ids) id: cards[id]!.toJson()},
    });
  }

  int get maxZ => cards.values.fold(0, (m, p) => math.max(m, p.z));

  /// Busca un hueco libre para una carta nueva, en espiral desde [near] (o el centro).
  Placement findFreeSpot({double? nearX, double? nearY, int seed = 0}) {
    final rnd = math.Random(seed);
    final cx = nearX ?? 0, cy = nearY ?? 0;
    const step = 70.0;
    for (var i = 0; i < 4000; i++) {
      final a = i * 0.62;
      final r = step * math.sqrt(i.toDouble()) * 1.4;
      final x = cx + math.cos(a) * r;
      final y = cy + math.sin(a) * r;
      final candidate = Placement(
        x: x,
        y: y,
        scale: 0.85 + rnd.nextDouble() * 0.35,
        rotation: (rnd.nextDouble() - 0.5) * 0.16,
        z: maxZ + 1,
      );
      final free = cards.values.every((p) {
        final minDist = (p.radius + candidate.radius) * 0.78;
        return math.pow(p.x - x, 2) + math.pow(p.y - y, 2) > minDist * minDist;
      });
      if (free) return candidate;
    }
    return Placement(x: cx, y: cy, z: maxZ + 1);
  }
}
