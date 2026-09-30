import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';

enum Sound { tap, pick, drop, whoosh, flip, reveal, shimmer }

/// Sonidos y vibraciones sutiles.
class Sfx {
  Sfx(this.settings);

  final AppSettings settings;
  final Map<Sound, AudioPlayer> _players = {};

  Future<void> play(Sound s, {double volume = 0.6}) async {
    if (!settings.sound) return;
    try {
      final player = _players.putIfAbsent(s, () => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
      await player.stop();
      await player.play(AssetSource('sounds/${s.name}.wav'), volume: volume);
    } catch (_) {
      // El sonido es decorativo: si falla, seguimos sin él.
    }
  }

  void light() {
    if (settings.haptics) HapticFeedback.selectionClick();
  }

  void medium() {
    if (settings.haptics) HapticFeedback.mediumImpact();
  }

  void heavy() {
    if (settings.haptics) HapticFeedback.heavyImpact();
  }
}
