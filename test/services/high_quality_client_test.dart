import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/services/high_quality_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responses);
  final List<(int, Object)> responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = responses.removeAt(0);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> playback(int quality, {int? claimedQuality}) => {
  'code': 0,
  'data': {
    'quality': claimedQuality ?? quality,
    'dash': {
      'video': [
        {'id': quality, 'baseUrl': 'https://media.example.test/video', 'codecs': 'avc1.640028'},
      ],
    },
    'support_formats': [
      {'quality': quality, 'codecs': ['avc1']},
    ],
    'accept_quality': [120, 112, 80],
  },
};

const identity = <String, dynamic>{
  'mid': '123', 'cookie': 'SESSDATA=synthetic-test-value', 'csrf': 'synthetic',
};

void main() {
  test('server URL accepts a base path but refuses embedded credentials or parameters', () {
    expect(HighQualityClient.parseServer(' https://service.example.test/base/ ')?.toString(), 'https://service.example.test/base');
    for (final invalid in ['file:///tmp/a', 'https://user:pass@example.test', 'https://example.test?token=a', 'https://example.test#part', 'example.test']) {
      expect(HighQualityClient.parseServer(invalid), isNull);
    }
  });

  test('advertised quality without a matching stream is rejected', () {
    expect(HighQualityClient.playableData(playback(80, claimedQuality: 120)), isNull);
    final data = HighQualityClient.playableData(playback(112));
    expect(data?['accept_quality'], [112]);
  });

  test('non-HTTP media URLs cannot reach the player', () {
    final response = playback(120);
    response['data']['dash']['video'][0]['baseUrl'] = 'file:///private/secret';
    expect(HighQualityClient.playableData(response), isNull);
  });

  test('account handshake precedes playback and credentials stay in its JSON body', () async {
    final adapter = FakeAdapter([
      (200, {'code': 0, 'coin': 1, 'version': '0.0.6'}),
      (200, playback(120)),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final states = <String>[];
    final client = HighQualityClient(server: Uri.parse('http://service.example.test'), dio: dio, onStatus: states.add);
    final result = await client.resolve(identity: identity, playUrl: Uri.parse('https://api.bilibili.com/x/player/playurl?cid=1&qn=120'), pgc: false, original: playback(80));
    expect(result?['quality'], 120);
    expect(adapter.requests.map((r) => r.uri.path), ['/api/bzusta', '/api/bzview2']);
    expect(jsonDecode(adapter.requests.first.data)['ui'], identity);
    expect(adapter.requests.every((r) => r.followRedirects == false), isTrue);
    expect(adapter.requests.every((r) => !r.headers.keys.any((k) => k.toLowerCase() == 'cookie')), isTrue);
    expect(states.join(), isNot(contains('synthetic-test-value')));
    expect(states.join(), isNot(contains('media.example.test')));
    client.close();
  });

  test('quota exhaustion avoids the playback request', () async {
    final adapter = FakeAdapter([(200, {'code': 0, 'coin': 0, 'version': '0.0.6'})]);
    final client = HighQualityClient(server: Uri.parse('https://service.example.test'), dio: Dio()..httpClientAdapter = adapter);
    expect(await client.resolve(identity: identity, playUrl: Uri.parse('https://api.bilibili.com/x/player/playurl'), pgc: false, original: playback(80)), isNull);
    expect(adapter.requests, hasLength(1));
    client.close();
  });

  test('service redirects fall back without resending credentials', () async {
    final adapter = FakeAdapter([(302, {'location': 'https://another.example.test'})]);
    final client = HighQualityClient(server: Uri.parse('https://service.example.test'), dio: Dio()..httpClientAdapter = adapter);
    expect(await client.resolve(identity: identity, playUrl: Uri.parse('https://api.bilibili.com/x/player/playurl'), pgc: false, original: playback(80)), isNull);
    expect(adapter.requests, hasLength(1));
    client.close();
  });

  test('equal or lower quality retains the original stream', () async {
    final adapter = FakeAdapter([(200, {'code': 0, 'coin': 1}), (200, playback(80))]);
    final client = HighQualityClient(server: Uri.parse('https://service.example.test'), dio: Dio()..httpClientAdapter = adapter);
    expect(await client.resolve(identity: identity, playUrl: Uri.parse('https://api.bilibili.com/x/player/playurl'), pgc: false, original: playback(120)), isNull);
    client.close();
  });

  test('PGC uses bzview3 and normalizes a video_info response', () async {
    final data = playback(120)['data'];
    final adapter = FakeAdapter([
      (200, {'code': 0, 'coin': 1}),
      (200, {'code': 0, 'result': {'video_info': data}}),
    ]);
    final client = HighQualityClient(server: Uri.parse('https://service.example.test'), dio: Dio()..httpClientAdapter = adapter);
    final result = await client.resolve(identity: identity, playUrl: Uri.parse('https://api.bilibili.com/pgc/player/web/v2/playurl'), pgc: true, original: playback(80));
    expect(result?['quality'], 120);
    expect(adapter.requests.last.uri.path, '/api/bzview3');
    client.close();
  });
}
