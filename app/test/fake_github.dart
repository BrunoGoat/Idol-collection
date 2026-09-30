import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idol_collection/data/local_store.dart';

/// Un repo de GitHub en memoria que entiende los endpoints que usa la app.
class FakeGitHub {
  final Map<String, Uint8List> files = {};
  final Map<String, Uint8List> _blobs = {};
  final Map<String, Map<String, Uint8List>> _trees = {};
  final Map<String, String> _commitTree = {};
  int commits = 0;
  int blobDownloads = 0;
  String head = 'c0';

  void seedFromDisk(String dir, String prefix) {
    for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
      final rel = f.path.substring(dir.length + 1).replaceAll('\\', '/');
      files['$prefix/$rel'] = f.readAsBytesSync();
    }
  }

  void put(String path, String text) => files[path] = Uint8List.fromList(utf8.encode(text));
  String? text(String path) => files[path] == null ? null : utf8.decode(files[path]!);

  http.Client client() => MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    final path = req.url.path.replaceFirst(RegExp(r'^/repos/[^/]+/[^/]+'), '');
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    if (req.method == 'GET' && path.startsWith('/git/trees/')) {
      return json({
        'tree': [
          for (final e in files.entries) {'path': e.key, 'type': 'blob', 'sha': gitBlobSha(e.value), 'size': e.value.length},
        ],
      });
    }
    if (req.method == 'GET' && path.startsWith('/git/blobs/')) {
      final sha = path.split('/').last;
      final match = files.values.where((b) => gitBlobSha(b) == sha);
      if (match.isEmpty) return json({'message': 'Not Found'}, 404);
      blobDownloads++;
      return http.Response.bytes(match.first, 200);
    }
    if (req.method == 'GET' && path.startsWith('/git/ref/heads/')) {
      return json({'object': {'sha': head}});
    }
    if (req.method == 'GET' && path.startsWith('/git/commits/')) {
      return json({'tree': {'sha': 'tree-of-$head'}});
    }
    if (req.method == 'GET' && path.startsWith('/contents/')) {
      final p = Uri.decodeComponent(path.substring('/contents/'.length));
      final b = files[p];
      return b == null ? json({'message': 'Not Found'}, 404) : http.Response.bytes(b, 200);
    }
    final body = req.body.isEmpty ? <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    if (req.method == 'POST' && path == '/git/blobs') {
      final bytes = base64Decode(body['content'] as String);
      final sha = gitBlobSha(bytes);
      _blobs[sha] = bytes;
      return json({'sha': sha}, 201);
    }
    if (req.method == 'POST' && path == '/git/trees') {
      final next = Map<String, Uint8List>.from(files);
      for (final e in (body['tree'] as List).cast<Map<String, dynamic>>()) {
        final sha = e['sha'] as String?;
        if (sha == null) {
          if (!next.containsKey(e['path'])) return json({'message': 'GitRPC::BadObjectState'}, 422);
          next.remove(e['path']);
        } else {
          next[e['path'] as String] = _blobs[sha]!;
        }
      }
      final id = 't${_trees.length}';
      _trees[id] = next;
      return json({'sha': id}, 201);
    }
    if (req.method == 'POST' && path == '/git/commits') {
      final id = 'c${_commitTree.length + 1}';
      _commitTree[id] = body['tree'] as String;
      return json({'sha': id}, 201);
    }
    if (req.method == 'PATCH' && path.startsWith('/git/refs/heads/')) {
      final sha = body['sha'] as String;
      files
        ..clear()
        ..addAll(_trees[_commitTree[sha]]!);
      head = sha;
      commits++;
      return json({'object': {'sha': sha}});
    }
    return json({'message': 'unexpected ${req.method} $path'}, 500);
  }
}
