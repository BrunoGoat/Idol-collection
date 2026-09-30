import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';

import '../app_scope.dart';
import '../models/catalog.dart';
import '../models/idol.dart';
import '../widgets/stamp_card.dart';

class EditorResult {
  EditorResult(this.idol, this.image);
  final Idol idol;
  final Uint8List? image;
}

/// Crear o editar una carta, con vista previa en vivo.
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({super.key, this.existing});

  final Idol? existing;

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> with SingleTickerProviderStateMixin {
  late final Idol _draft = widget.existing?.copy() ?? Idol(id: 'nuevo', name: '', rarity: Rarity.epic, frame: 'oro');
  final time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((e) => time.value = e.inMicroseconds / 1e6)..start();

  late final _name = TextEditingController(text: _draft.name);
  late final _title = TextEditingController(text: _draft.title ?? '');
  late final _category = TextEditingController(text: _draft.category ?? '');
  late final _quote = TextEditingController(text: _draft.quote ?? '');
  late final _body = TextEditingController(text: _draft.body);

  Uint8List? _newImage;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _ticker.dispose();
    for (final c in [_name, _title, _category, _quote, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  ImageProvider? get _preview {
    if (_newImage != null) return MemoryImage(_newImage!);
    if (widget.existing != null) return FileImage(AppScope.of(context).collection.imageFile(widget.existing!));
    return null;
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 95);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _newImage = bytes;
        _draft.focusX = 0;
        _draft.focusY = 0;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir la imagen: $e')));
    }
  }

  void _chooseSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Sacar una foto'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _syncText() {
    _draft
      ..name = _name.text.trim()
      ..title = _title.text.trim().isEmpty ? null : _title.text.trim()
      ..category = _category.text.trim().isEmpty ? null : _category.text.trim()
      ..quote = _quote.text.trim().isEmpty ? null : _quote.text.trim()
      ..body = _body.text.trim();
  }

  Future<void> _save() async {
    _syncText();
    if (_draft.name.isEmpty) {
      _snack('Ponele un nombre a tu ídolo.');
      return;
    }
    if (_isNew && _newImage == null) {
      _snack('Elegí una imagen para la carta.');
      return;
    }
    if (_isNew) {
      Navigator.pop(context, EditorResult(_draft, _newImage));
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).collection.updateIdol(_draft, newImage: _newImage);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('No se pudo guardar: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _draft.added,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _draft.added = d);
  }

  @override
  Widget build(BuildContext context) {
    final categories = AppScope.of(context).collection.categories.toList()..sort();
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuevo ídolo' : 'Editar a ${widget.existing!.name}'),
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Guardar')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SizedBox(height: 16),
          // Vista previa en vivo. Arrastrá sobre la imagen para encuadrarla.
          Center(
            child: GestureDetector(
              onTap: preview == null ? _chooseSource : null,
              onPanUpdate: preview == null
                  ? null
                  : (d) => setState(() {
                        _draft.focusX = (_draft.focusX - d.delta.dx / 90).clamp(-1.0, 1.0);
                        _draft.focusY = (_draft.focusY - d.delta.dy / 90).clamp(-1.0, 1.0);
                      }),
              child: SizedBox(
                height: 330,
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_name, _title]),
                      builder: (context, _) {
                        final shown = _draft.copy()
                          ..name = _name.text.isEmpty ? 'Tu ídolo' : _name.text
                          ..title = _title.text.isEmpty ? null : _title.text;
                        return StampCard(
                          idol: shown,
                          number: _draft.number ?? AppScope.of(context).collection.idols.length + 1,
                          image: preview,
                          time: time,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _chooseSource,
                  icon: const Icon(Icons.image),
                  label: Text(preview == null ? 'Elegir imagen' : 'Cambiar imagen'),
                ),
                if (preview != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('Arrastrá la carta para encuadrar', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ),
              ],
            ),
          ),
          const _Section('Identidad'),
          _field(_name, 'Nombre', hint: 'Ej: Ayrton Senna'),
          _field(_title, 'Título épico (opcional)', hint: 'Ej: El Mago de la Lluvia'),
          _field(_category, 'Categoría (opcional)', hint: 'Ej: Deporte, Música, Ciencia…'),
          if (categories.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(label: Text(c), onPressed: () => setState(() => _category.text = c)),
                    ),
                ],
              ),
            ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Fecha de ingreso al salón'),
            subtitle: Text(postmarkDate(_draft.added)),
            onTap: _pickDate,
          ),
          const _Section('Rareza'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in Rarity.values)
                  ChoiceChip(
                    selected: _draft.rarity == r,
                    onSelected: (_) => setState(() => _draft.rarity = r),
                    avatar: Text('★' * r.stars, style: TextStyle(color: r.color, fontSize: 10)),
                    label: Text(r.label),
                    selectedColor: r.color.withValues(alpha: 0.3),
                    side: BorderSide(color: r.color),
                  ),
              ],
            ),
          ),
          _Section('Marco · ${_draft.frameStyle.name}'),
          SizedBox(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: kFrames.length,
              itemBuilder: (context, i) {
                final f = kFrames[i];
                final selected = f.id == _draft.frame;
                return GestureDetector(
                  onTap: () => setState(() => _draft.frame = f.id),
                  child: Container(
                    width: 100,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? Colors.amber : Colors.transparent, width: 2),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: StampCard(
                                idol: _draft.copy()
                                  ..frame = f.id
                                  ..name = _name.text.isEmpty ? f.name : _name.text,
                                number: 1,
                                image: preview,
                                time: time,
                                animate: selected,
                              ),
                            ),
                          ),
                        ),
                        Text(f.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _Section('Fuente · ${_draft.fontOption.name}'),
          SizedBox(
            height: 76,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: kFonts.length,
              itemBuilder: (context, i) {
                final f = kFonts[i];
                final selected = f.id == _draft.font;
                final sample = _name.text.isEmpty ? f.name : _name.text;
                return GestureDetector(
                  onTap: () => setState(() => _draft.font = f.id),
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: selected ? 0.12 : 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selected ? Colors.amber : Colors.white12, width: selected ? 2 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, child: Text(f.apply(sample), style: f.style(22, color: Colors.white))),
                        const SizedBox(height: 2),
                        Text(f.name, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const _Section('Por qué lo admiro'),
          _field(_quote, 'Frase célebre (opcional)', hint: 'Una frase suya que te marcó'),
          _field(
            _body,
            'Lo que hizo para que lo idolatre',
            hint: 'Escribí libremente. Podés usar **negrita**, _cursiva_ y listas con -.',
            lines: 8,
          ),
          if (!_isNew)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('¿Quitar a ${widget.existing!.name}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await AppScope.of(context).collection.deleteIdol(widget.existing!.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar de la colección'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 20,
          textCapitalization: lines == 1 ? TextCapitalization.words : TextCapitalization.sentences,
          onChanged: (_) => setState(_syncText),
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), alignLabelWithHint: true),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(fontFamily: kTitleFont, letterSpacing: 2, fontSize: 13, color: Colors.amber),
        ),
      );
}
