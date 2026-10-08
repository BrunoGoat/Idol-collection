import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../board/board_layers.dart';
import '../models/catalog.dart';
import '../models/idol.dart';

/// Buscador: devuelve el id del ídolo elegido para que la cámara vuele hasta él.
Future<String?> showSearchSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF0101018),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _SearchSheet(),
    );

class _SearchSheet extends StatefulWidget {
  const _SearchSheet();

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _query = '';
  String? _category;
  Rarity? _rarity;

  bool _matches(Idol i) {
    final q = _query.toLowerCase().trim();
    if (_category != null && i.category != _category) return false;
    if (_rarity != null && i.rarity != _rarity) return false;
    if (q.isEmpty) return true;
    return [i.name, i.title, i.category, i.quote, i.body].any((s) => s?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final collection = AppScope.of(context).collection;
    final categories = collection.categories.toList()..sort();
    final results = collection.sortedIdols.where(_matches).toList();
    final height = MediaQuery.sizeOf(context).height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Buscar por nombre, título, texto…',
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final r in Rarity.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilterChip(
                        label: Text(r.label),
                        selected: _rarity == r,
                        selectedColor: r.color.withValues(alpha: 0.3),
                        side: BorderSide(color: r.color.withValues(alpha: 0.6)),
                        onSelected: (s) => setState(() => _rarity = s ? r : null),
                      ),
                    ),
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilterChip(
                        label: Text(c),
                        selected: _category == c,
                        selectedColor: categoryColor(c).withValues(alpha: 0.3),
                        onSelected: (s) => setState(() => _category = s ? c : null),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('Nada por acá', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final idol = results[i];
                        return ListTile(
                          onTap: () => Navigator.pop(context, idol.id),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 42,
                              height: 56,
                              child: Image(
                                image: collection.imageOf(idol, thumb: true, width: 120),
                                fit: BoxFit.cover,
                                alignment: Alignment(idol.focusX, idol.focusY),
                                errorBuilder: (_, _, _) => ColoredBox(color: idol.rarity.color),
                              ),
                            ),
                          ),
                          title: Text(idol.name, style: idol.fontOption.style(18, color: Colors.white)),
                          subtitle: Text(
                            [idol.title, idol.category].whereType<String>().join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text('★' * idol.rarity.stars, style: TextStyle(color: idol.rarity.color)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
