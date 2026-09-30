import 'package:flutter/material.dart';

/// Tamaño base de una carta en coordenadas del tablero (proporción estampilla).
const double kCardW = 240;
const double kCardH = 320;

// ---------------------------------------------------------------------------
// Rarezas
// ---------------------------------------------------------------------------

enum Rarity { common, rare, epic, legendary, mythic }

extension RarityInfo on Rarity {
  String get label => const ['Común', 'Rara', 'Épica', 'Legendaria', 'Mítica'][index];

  Color get color => const [
        Color(0xFFCFD8DC),
        Color(0xFF40A9FF),
        Color(0xFFB45CFF),
        Color(0xFFFFC23D),
        Color(0xFFFF3D8B),
      ][index];

  int get stars => index + 1;

  /// Intensidad del brillo (0..1).
  double get glow => const [0.18, 0.4, 0.62, 0.85, 1.0][index];

  /// Velocidad del pulso del brillo.
  double get pulseSpeed => const [0.6, 0.8, 1.0, 1.2, 1.5][index];

  /// El brillo de las míticas cicla por todo el arcoíris.
  bool get rainbow => this == Rarity.mythic;

  /// Frecuencia del reflejo que recorre la carta (0 = nunca).
  double get shineEvery => const [0.0, 9.0, 7.0, 5.0, 3.5][index];

  static Rarity parse(Object? value) {
    final s = value?.toString().toLowerCase().trim() ?? '';
    const aliases = {
      'comun': Rarity.common,
      'común': Rarity.common,
      'common': Rarity.common,
      'rara': Rarity.rare,
      'rare': Rarity.rare,
      'epica': Rarity.epic,
      'épica': Rarity.epic,
      'epic': Rarity.epic,
      'legendaria': Rarity.legendary,
      'legendary': Rarity.legendary,
      'mitica': Rarity.mythic,
      'mítica': Rarity.mythic,
      'mythic': Rarity.mythic,
    };
    return aliases[s] ?? Rarity.rare;
  }
}

// ---------------------------------------------------------------------------
// Marcos de estampilla
// ---------------------------------------------------------------------------

enum Ornament { none, corners, filigree, stars, circuit, flames, crystals, laurel, runes }

enum FrameFx { none, holo, fire, neon, cosmic, aged, frost }

class FrameStyle {
  const FrameStyle({
    required this.id,
    required this.name,
    required this.paper,
    required this.border,
    required this.border2,
    required this.ink,
    this.ornament = Ornament.none,
    this.fx = FrameFx.none,
    this.band,
  });

  final String id;
  final String name;

  /// Degradé del papel de la estampilla (de arriba-izquierda a abajo-derecha).
  final List<Color> paper;

  /// Filete interior principal y secundario.
  final Color border;
  final Color border2;

  /// Color de la tinta (textos impresos sobre el papel).
  final Color ink;

  final Ornament ornament;
  final FrameFx fx;

  /// Color de la banda donde va el nombre. Por defecto, derivado del papel.
  final Color? band;

  bool get isDark => paper.first.computeLuminance() < 0.3;
}

const List<FrameStyle> kFrames = [
  FrameStyle(
    id: 'clasico',
    name: 'Clásico',
    paper: [Color(0xFFFFFDF6), Color(0xFFF1EADB)],
    border: Color(0xFF8B1E1E),
    border2: Color(0xFF1E3A8B),
    ink: Color(0xFF2B2118),
    ornament: Ornament.corners,
  ),
  FrameStyle(
    id: 'oro',
    name: 'Oro Imperial',
    paper: [Color(0xFFFFE9A8), Color(0xFFD4A33B), Color(0xFFFFF0B8), Color(0xFFB8860B)],
    border: Color(0xFF6B4A00),
    border2: Color(0xFFFFF6D5),
    ink: Color(0xFF3D2800),
    ornament: Ornament.filigree,
  ),
  FrameStyle(
    id: 'plata',
    name: 'Plata Lunar',
    paper: [Color(0xFFF4F6F8), Color(0xFFB9C2CC), Color(0xFFEFF3F6), Color(0xFF8E99A6)],
    border: Color(0xFF3A4550),
    border2: Color(0xFFFFFFFF),
    ink: Color(0xFF1D252D),
    ornament: Ornament.laurel,
  ),
  FrameStyle(
    id: 'obsidiana',
    name: 'Obsidiana',
    paper: [Color(0xFF1B1B22), Color(0xFF050507)],
    border: Color(0xFFD4AF37),
    border2: Color(0xFF6E5A1E),
    ink: Color(0xFFF3D98B),
    ornament: Ornament.filigree,
  ),
  FrameStyle(
    id: 'pergamino',
    name: 'Pergamino Antiguo',
    paper: [Color(0xFFE9D3A3), Color(0xFFC9A66B)],
    border: Color(0xFF5B3A18),
    border2: Color(0xFF8C6239),
    ink: Color(0xFF3B2410),
    ornament: Ornament.runes,
    fx: FrameFx.aged,
  ),
  FrameStyle(
    id: 'neon',
    name: 'Neón',
    paper: [Color(0xFF0B0620), Color(0xFF14003A)],
    border: Color(0xFF00F0FF),
    border2: Color(0xFFFF2BD6),
    ink: Color(0xFFB9FBFF),
    ornament: Ornament.circuit,
    fx: FrameFx.neon,
  ),
  FrameStyle(
    id: 'holografico',
    name: 'Holográfico',
    paper: [Color(0xFFE0F7FF), Color(0xFFF7E0FF), Color(0xFFFFF7D6), Color(0xFFD6FFE9)],
    border: Color(0xFF6A5ACD),
    border2: Color(0xFFFFFFFF),
    ink: Color(0xFF2A1F5C),
    ornament: Ornament.stars,
    fx: FrameFx.holo,
  ),
  FrameStyle(
    id: 'carmesi',
    name: 'Carmesí Real',
    paper: [Color(0xFF8E0E1C), Color(0xFF4A0610)],
    border: Color(0xFFFFD36B),
    border2: Color(0xFFB8860B),
    ink: Color(0xFFFFE7A8),
    ornament: Ornament.filigree,
  ),
  FrameStyle(
    id: 'esmeralda',
    name: 'Esmeralda',
    paper: [Color(0xFF0F6B4A), Color(0xFF03301F)],
    border: Color(0xFFC9F2D8),
    border2: Color(0xFFD4AF37),
    ink: Color(0xFFE6FFF1),
    ornament: Ornament.laurel,
  ),
  FrameStyle(
    id: 'cosmico',
    name: 'Cósmico',
    paper: [Color(0xFF1A0B3D), Color(0xFF050214), Color(0xFF2B0B4F)],
    border: Color(0xFFB9A7FF),
    border2: Color(0xFF5D3FD3),
    ink: Color(0xFFE9E2FF),
    ornament: Ornament.stars,
    fx: FrameFx.cosmic,
  ),
  FrameStyle(
    id: 'hielo',
    name: 'Cristal de Hielo',
    paper: [Color(0xFFE8FBFF), Color(0xFFA9DDF0)],
    border: Color(0xFF2A7FA8),
    border2: Color(0xFFFFFFFF),
    ink: Color(0xFF0D3B54),
    ornament: Ornament.crystals,
    fx: FrameFx.frost,
  ),
  FrameStyle(
    id: 'fuego',
    name: 'Fuego Eterno',
    paper: [Color(0xFF3A0500), Color(0xFF120100)],
    border: Color(0xFFFF7A00),
    border2: Color(0xFFFFD000),
    ink: Color(0xFFFFE3B0),
    ornament: Ornament.flames,
    fx: FrameFx.fire,
  ),
];

FrameStyle frameById(String? id) =>
    kFrames.firstWhere((f) => f.id == id, orElse: () => kFrames.first);

// ---------------------------------------------------------------------------
// Fuentes épicas
// ---------------------------------------------------------------------------

class FontOption {
  const FontOption(this.id, this.name, {this.size = 1.0, this.spacing = 1.0, this.upper = false});

  /// Coincide con la `family` declarada en pubspec.yaml.
  final String id;
  final String name;

  /// Algunas fuentes son más grandes o chicas de por sí: esto las empareja.
  final double size;
  final double spacing;
  final bool upper;

  TextStyle style(double fontSize, {Color? color, List<Shadow>? shadows}) => TextStyle(
        fontFamily: id,
        fontSize: fontSize * size,
        letterSpacing: spacing * fontSize * 0.06,
        color: color,
        shadows: shadows,
        height: 1.1,
      );

  String apply(String text) => upper ? text.toUpperCase() : text;
}

const List<FontOption> kFonts = [
  FontOption('Cinzel', 'Cinzel', upper: true),
  FontOption('CinzelDecorative', 'Cinzel Decorative', size: 0.95),
  FontOption('UncialAntiqua', 'Uncial Antiqua'),
  FontOption('MedievalSharp', 'Medieval Sharp'),
  FontOption('PirataOne', 'Pirata One', size: 1.15),
  FontOption('UnifrakturMaguntia', 'Fraktur', size: 1.1),
  FontOption('GrenzeGotisch', 'Grenze Gotisch', size: 1.1),
  FontOption('Metamorphous', 'Metamorphous', size: 0.95),
  FontOption('AlmendraDisplay', 'Almendra', size: 1.1),
  FontOption('NewRocker', 'New Rocker', size: 1.05),
  FontOption('MetalMania', 'Metal Mania', size: 1.1),
  FontOption('Orbitron', 'Orbitron', size: 0.85, spacing: 2, upper: true),
  FontOption('Audiowide', 'Audiowide', size: 0.9),
  FontOption('Bungee', 'Bungee', size: 0.85, upper: true),
  FontOption('BlackOpsOne', 'Black Ops', size: 0.95),
  FontOption('BebasNeue', 'Bebas Neue', size: 1.25, spacing: 2),
  FontOption('Monoton', 'Monoton', size: 0.9),
  FontOption('PressStart2P', 'Press Start 2P', size: 0.6, spacing: 0),
  FontOption('GreatVibes', 'Great Vibes', size: 1.35, spacing: 0),
  FontOption('Rye', 'Rye (western)', size: 0.95),
  FontOption('MarcellusSC', 'Marcellus', size: 1.0, spacing: 1.5),
];

FontOption fontById(String? id) =>
    kFonts.firstWhere((f) => f.id == id, orElse: () => kFonts.first);

/// Fuente de texto corrido para toda la interfaz.
const String kBodyFont = 'CormorantGaramond';
const String kTitleFont = 'Cinzel';
