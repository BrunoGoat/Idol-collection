import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idol_collection/data/github_client.dart';

void main() {
  test('lee el último release y resuelve el enlace del APK sin reenviar el token', () async {
    final seen = <String, Map<String, String>>{};
    final client = GitHubClient(
      token: 'tok',
      owner: 'BrunoGoat',
      repo: 'Idol-collection',
      branch: 'main',
      httpClient: MockClient((req) async {
        seen[req.url.path] = req.headers;
        if (req.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'app-v1.0.7',
              'body': 'Notas',
              'assets': [
                {'id': 11, 'name': 'otro.txt'},
                {'id': 42, 'name': 'salon-de-idolos.apk'},
              ],
            }),
            200,
          );
        }
        if (req.url.path.endsWith('/releases/assets/42')) {
          expect(req.followRedirects, isFalse);
          return http.Response('', 302, headers: {'location': 'https://objects.example/firmado.apk'});
        }
        return http.Response('{}', 404);
      }),
    );
    final release = await client.latestRelease();
    expect(release!.tag, 'app-v1.0.7');
    expect(release.apkAssetId, 42);
    expect(await client.assetDownloadUrl(42), 'https://objects.example/firmado.apk');
    expect(seen['/repos/BrunoGoat/Idol-collection/releases/assets/42']!['Accept'], 'application/octet-stream');
  });
}
