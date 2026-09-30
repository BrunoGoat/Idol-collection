import 'package:flutter/widgets.dart';

import 'data/collection.dart';
import 'data/settings.dart';
import 'services/sfx.dart';

/// Da acceso a la colección, los ajustes y los sonidos desde cualquier pantalla.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.collection,
    required this.settings,
    required this.sfx,
    required super.child,
  });

  final Collection collection;
  final AppSettings settings;
  final Sfx sfx;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => old.collection != collection || old.settings != settings;
}
