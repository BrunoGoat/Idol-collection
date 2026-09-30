import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'board/board_screen.dart';
import 'data/collection.dart';
import 'data/settings.dart';
import 'models/catalog.dart';
import 'services/sfx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final settings = AppSettings();
  await settings.load();
  final collection = await Collection.open(settings);
  runApp(IdolApp(settings: settings, collection: collection));
}

class IdolApp extends StatelessWidget {
  const IdolApp({super.key, required this.settings, required this.collection});

  final AppSettings settings;
  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFFC23D), brightness: Brightness.dark);
    return AppScope(
      collection: collection,
      settings: settings,
      sfx: Sfx(settings),
      child: MaterialApp(
        title: 'Salón de Ídolos',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: scheme,
          scaffoldBackgroundColor: const Color(0xFF0C0B10),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0C0B10),
            titleTextStyle: TextStyle(fontFamily: kTitleFont, fontSize: 18, color: Colors.white, letterSpacing: 1),
          ),
        ),
        home: const BoardScreen(),
      ),
    );
  }
}
