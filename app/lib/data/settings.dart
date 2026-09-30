import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de la app. El token de GitHub se guarda cifrado en el teléfono.
class AppSettings extends ChangeNotifier {
  static const _secure = FlutterSecureStorage();

  String owner = 'BrunoGoat';
  String repo = 'Idol-collection';
  String branch = 'main';
  String token = '';
  bool sound = true;
  bool haptics = true;
  bool idolOfTheDay = true;
  bool tiltHolo = true;
  bool constellations = true;

  late SharedPreferences _prefs;

  bool get isConfigured => token.isNotEmpty && owner.isNotEmpty && repo.isNotEmpty && branch.isNotEmpty;
  String get repoKey => '$owner/$repo@$branch';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    owner = _prefs.getString('owner') ?? owner;
    repo = _prefs.getString('repo') ?? repo;
    branch = _prefs.getString('branch') ?? branch;
    sound = _prefs.getBool('sound') ?? sound;
    haptics = _prefs.getBool('haptics') ?? haptics;
    idolOfTheDay = _prefs.getBool('idolOfTheDay') ?? idolOfTheDay;
    tiltHolo = _prefs.getBool('tiltHolo') ?? tiltHolo;
    constellations = _prefs.getBool('constellations') ?? constellations;
    try {
      token = await _secure.read(key: 'github_token') ?? '';
    } catch (_) {
      token = '';
    }
  }

  Future<void> saveRepo({required String owner, required String repo, required String branch, required String token}) async {
    this.owner = owner.trim();
    this.repo = repo.trim();
    this.branch = branch.trim();
    this.token = token.trim();
    await _prefs.setString('owner', this.owner);
    await _prefs.setString('repo', this.repo);
    await _prefs.setString('branch', this.branch);
    await _secure.write(key: 'github_token', value: this.token);
    notifyListeners();
  }

  Future<void> setFlag(String key, bool value) async {
    switch (key) {
      case 'sound':
        sound = value;
      case 'haptics':
        haptics = value;
      case 'idolOfTheDay':
        idolOfTheDay = value;
      case 'tiltHolo':
        tiltHolo = value;
      case 'constellations':
        constellations = value;
    }
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  /// Ídolos ya vistos (para saber cuáles son nuevos y mostrarlos con animación).
  Set<String> get seenIds => {...?_prefs.getStringList('seen_ids')};
  Future<void> setSeenIds(Set<String> ids) => _prefs.setStringList('seen_ids', ids.toList());
  bool get hasSeenAnything => _prefs.containsKey('seen_ids');

  bool get seenTutorial => _prefs.getBool('seen_tutorial') ?? false;
  Future<void> setSeenTutorial() async {
    await _prefs.setBool('seen_tutorial', true);
    notifyListeners();
  }

  String? get lastIdolOfDay => _prefs.getString('last_idol_of_day');
  Future<void> setLastIdolOfDay(String v) => _prefs.setString('last_idol_of_day', v);
}
