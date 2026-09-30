import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_scope.dart';
import '../models/catalog.dart';
import '../models/idol.dart';
import '../widgets/backgrounds.dart';
import '../widgets/glass.dart';
import '../widgets/stamp_card.dart';

/// Galería de fondos, marcos y fuentes para elegir con los ojos.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> with SingleTickerProviderStateMixin {
  final time = ValueNotifier<double>(0);
  final camera = ValueNotifier<CameraView>(CameraView.zero);
  late final Ticker _ticker = createTicker((e) {
    final t = e.inMicroseconds / 1e6;
    time.value = t;
    // La cámara se mece para que se note la profundidad de cada fondo.
    camera.value = CameraView(Offset(math.sin(t * 0.25) * 260, math.cos(t * 0.18) * 160), 1);
  })..start();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<Idol> _samples(BuildContext context) {
    final real = AppScope.of(context).collection.sortedIdols.take(3).toList();
    if (real.isNotEmpty) return real;
    return [
      Idol(id: 'a', name: 'Leyenda', title: 'Tu primer ídolo', rarity: Rarity.legendary, frame: 'oro', font: 'CinzelDecorative'),
      Idol(id: 'b', name: 'Heroína', rarity: Rarity.epic, frame: 'cosmico', font: 'UncialAntiqua'),
      Idol(id: 'c', name: 'Maestro', rarity: Rarity.mythic, frame: 'neon', font: 'Orbitron'),
    ];
  }

  ImageProvider? _imageOf(BuildContext context, Idol idol) {
    final collection = AppScope.of(context).collection;
    if (!collection.idols.containsKey(idol.id)) return null;
    final thumb = collection.thumbs[idol.id];
    return thumb != null ? FileImage(thumb) : FileImage(collection.imageFile(idol));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Fondos (20)'),
            Tab(text: 'Marcos'),
            Tab(text: 'Fuentes'),
          ]),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [_themes(context), _frames(context), _fonts(context)],
        ),
      ),
    );
  }

  Widget _themes(BuildContext context) {
    final collection = AppScope.of(context).collection;
    final samples = _samples(context);
    final current = kThemes.indexWhere((t) => t.id == collection.layout.theme);
    return ListenableBuilder(
      listenable: collection,
      builder: (context, _) => PageView.builder(
        controller: PageController(initialPage: math.max(0, current)),
        itemCount: kThemes.length,
        itemBuilder: (context, i) {
          final theme = kThemes[i];
          final inUse = theme.id == collection.layout.theme;
          return Stack(
            children: [
              Positioned.fill(child: BoardBackground(theme: theme, time: time, camera: camera)),
              Center(
                child: SizedBox(
                  height: 300,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var k = 0; k < samples.length; k++)
                        Transform.translate(
                          offset: Offset((k - (samples.length - 1) / 2) * 110, k.isEven ? 10 : -14),
                          child: Transform.rotate(
                            angle: (k - 1) * 0.12,
                            child: SizedBox(
                              width: 150,
                              height: 200,
                              child: FittedBox(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: StampCard(
                                    idol: samples[k],
                                    number: k + 1,
                                    image: _imageOf(context, samples[k]),
                                    time: time,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
                child: Glass(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${i + 1} / ${kThemes.length}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(
                        theme.name,
                        style: TextStyle(fontFamily: 'CinzelDecorative', fontSize: 22, color: Colors.white, shadows: [Shadow(color: theme.accent, blurRadius: 12)]),
                      ),
                      const SizedBox(height: 4),
                      Text(theme.description, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: inUse ? null : () => collection.setTheme(theme.id),
                        icon: Icon(inUse ? Icons.check : Icons.wallpaper),
                        label: Text(inUse ? 'En uso' : 'Usar este fondo'),
                      ),
                      const SizedBox(height: 4),
                      const Text('Deslizá para ver otros', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _frames(BuildContext context) {
    final base = _samples(context).first;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.66),
      itemCount: kFrames.length,
      itemBuilder: (context, i) {
        final f = kFrames[i];
        final idol = base.copy()..frame = f.id;
        return Column(
          children: [
            Expanded(
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: StampCard(idol: idol, number: i + 1, image: _imageOf(context, base), time: time),
                ),
              ),
            ),
            Text(f.name, style: const TextStyle(fontFamily: kTitleFont, fontSize: 13)),
            Text('frame: ${f.id}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _fonts(BuildContext context) {
    final samples = _samples(context);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: kFonts.length,
      separatorBuilder: (_, _) => const Divider(color: Colors.white12),
      itemBuilder: (context, i) {
        final f = kFonts[i];
        final name = samples[i % samples.length].name;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  f.apply(name),
                  style: f.style(38, color: Colors.white, shadows: [const Shadow(color: Color(0xFFFFC23D), blurRadius: 14)]),
                ),
              ),
              Text('${i + 1}. ${f.name}   ·   font: ${f.id}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
        );
      },
    );
  }
}
