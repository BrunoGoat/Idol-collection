import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GitHubException implements Exception {
  GitHubException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => switch (status) {
        401 => 'Token inválido o vencido (401).',
        403 => 'Sin permiso sobre el repo (403). Revisá los permisos del token.',
        404 => 'No se encontró el repo o la rama (404).',
        0 => message,
        _ => 'GitHub respondió $status: $message',
      };
}

/// Un archivo del repo tal como lo describe el árbol de git.
class RemoteFile {
  RemoteFile(this.path, this.sha, this.size);
  final String path;
  final String sha;
  final int size;
}

/// Cliente mínimo de la API de GitHub. Lee con la API de árboles (un solo pedido
/// devuelve el SHA de cada archivo) y escribe commits atómicos con la API de git.
class GitHubClient {
  GitHubClient({
    required this.token,
    required this.owner,
    required this.repo,
    required this.branch,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String token;
  final String owner;
  final String repo;
  final String branch;
  final http.Client _http;

  String get _base => 'https://api.github.com/repos/$owner/$repo';

  Map<String, String> _headers([String accept = 'application/vnd.github+json']) => {
        'Authorization': 'Bearer $token',
        'Accept': accept,
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Future<Map<String, dynamic>> _getJson(String url) async {
    final r = await _http.get(Uri.parse(url), headers: _headers());
    _check(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _send(String method, String url, Map<String, dynamic> body) async {
    final req = http.Request(method, Uri.parse(url))
      ..headers.addAll(_headers())
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final r = await http.Response.fromStream(await _http.send(req));
    _check(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _check(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    var msg = r.body;
    try {
      msg = (jsonDecode(r.body) as Map)['message']?.toString() ?? r.body;
    } catch (_) {}
    throw GitHubException(r.statusCode, msg);
  }

  /// Todos los archivos bajo [prefix] con su SHA.
  Future<List<RemoteFile>> listFiles(String prefix) async {
    final j = await _getJson('$_base/git/trees/${Uri.encodeComponent(branch)}?recursive=1');
    final tree = (j['tree'] as List).cast<Map<String, dynamic>>();
    return [
      for (final e in tree)
        if (e['type'] == 'blob' && (e['path'] as String).startsWith(prefix))
          RemoteFile(e['path'] as String, e['sha'] as String, (e['size'] as num?)?.toInt() ?? 0),
    ];
  }

  Future<Uint8List> downloadBlob(String sha) async {
    final r = await _http.get(Uri.parse('$_base/git/blobs/$sha'), headers: _headers('application/vnd.github.raw'));
    _check(r);
    return r.bodyBytes;
  }

  /// Crea un único commit con todos los cambios. `null` = borrar el archivo.
  /// Si otro commit se metió en el medio, reintenta sobre la nueva punta.
  Future<void> commit(String message, Map<String, Uint8List?> files) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final ref = await _getJson('$_base/git/ref/heads/${Uri.encodeComponent(branch)}');
      final headSha = (ref['object'] as Map)['sha'] as String;
      final head = await _getJson('$_base/git/commits/$headSha');
      final baseTree = (head['tree'] as Map)['sha'] as String;

      final entries = <Map<String, dynamic>>[];
      for (final e in files.entries) {
        if (e.value == null) {
          entries.add({'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': null});
        } else {
          final blob = await _send('POST', '$_base/git/blobs', {
            'content': base64Encode(e.value!),
            'encoding': 'base64',
          });
          entries.add({'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']});
        }
      }
      final tree = await _send('POST', '$_base/git/trees', {'base_tree': baseTree, 'tree': entries});
      final commit = await _send('POST', '$_base/git/commits', {
        'message': message,
        'tree': tree['sha'],
        'parents': [headSha],
      });
      try {
        await _send('PATCH', '$_base/git/refs/heads/${Uri.encodeComponent(branch)}', {'sha': commit['sha']});
        return;
      } on GitHubException catch (e) {
        if (e.status != 422 || attempt == 2) rethrow; // 422 = no es fast-forward
      }
    }
  }

  /// Lee un archivo de texto de la punta actual de la rama (o null si no existe).
  Future<String?> readText(String path) async {
    final r = await _http.get(
      Uri.parse('$_base/contents/$path?ref=${Uri.encodeComponent(branch)}'),
      headers: _headers('application/vnd.github.raw'),
    );
    if (r.statusCode == 404) return null;
    _check(r);
    return utf8.decode(r.bodyBytes);
  }

  /// Último release publicado: (tag, notas, id del APK) o null si no hay.
  Future<({String tag, String notes, int? apkAssetId})?> latestRelease() async {
    final r = await _http.get(Uri.parse('$_base/releases/latest'), headers: _headers());
    if (r.statusCode == 404) return null;
    _check(r);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => (a['name'] as String? ?? '').endsWith('.apk')).firstOrNull;
    return (tag: j['tag_name'] as String? ?? '', notes: j['body'] as String? ?? '', apkAssetId: apk?['id'] as int?);
  }

  /// URL firmada y temporal para bajar un archivo de un release privado.
  /// GitHub responde con una redirección; la seguimos a mano para no mandarle
  /// el token al servidor de descargas.
  Future<String> assetDownloadUrl(int assetId) async {
    final req = http.Request('GET', Uri.parse('$_base/releases/assets/$assetId'))
      ..headers.addAll(_headers('application/octet-stream'))
      ..followRedirects = false;
    final r = await http.Response.fromStream(await _http.send(req));
    final location = r.headers['location'];
    if (r.statusCode >= 300 && r.statusCode < 400 && location != null) return location;
    _check(r);
    throw GitHubException(r.statusCode, 'GitHub no devolvió el enlace de descarga.');
  }

  void close() => _http.close();
}
