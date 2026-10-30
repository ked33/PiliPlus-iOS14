import 'dart:convert';

import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:dio/dio.dart';

/// Protocol shared with the user's 0.0.6 quality-enhancement userscript.
/// Uses a dedicated client: account interceptors, redirects and logging from
/// the main Bilibili client must never be attached to this connection.
class HighQualityClient {
  HighQualityClient({
    required this.server,
    Dio? dio,
    this.onStatus,
  }) : _dio = dio ?? Dio();

  final Uri server;
  final Dio _dio;
  final void Function(String message)? onStatus;
  final CancelToken _cancel = CancelToken();
  DateTime? _readyUntil;
  Future<bool>? _initializing;
  bool _closed = false;

  static Uri? parseServer(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  void close() {
    _closed = true;
    _cancel.cancel();
    _dio.close(force: true);
  }

  void _status(String message) {
    if (!_closed) onStatus?.call(message);
  }

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.postUri<Object?>(
      server.replace(path: '${server.path}$path'),
      data: jsonEncode(payload),
      cancelToken: _cancel,
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        followRedirects: false,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status == 200,
      ),
    );
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<bool> _initialize(Map<String, dynamic> identity) async {
    if (_readyUntil case final until? when until.isAfter(DateTime.now())) {
      return true;
    }
    if (_initializing case final task?) return task;
    final task = () async {
      _status('正在验证高画质账号');
      final response = await _post('/api/bzusta', {'ui': identity});
      if (response?['code'] != 0) {
        _status('账号验证失败，已使用原播放接口');
        return false;
      }
      final version = response?['version'];
      if (version != null && version.toString() != '0.0.6') {
        _status('高画质服务协议已更新，已使用原播放接口');
        return false;
      }
      final quota = response?['coin'];
      if (quota == false || quota == 0 || quota == '0') {
        _status('高画质服务配额不足，已使用原播放接口');
        return false;
      }
      _readyUntil = DateTime.now().add(const Duration(minutes: 15));
      return true;
    }();
    _initializing = task;
    try {
      return await task;
    } finally {
      _initializing = null;
    }
  }

  /// Returns a playurl payload only when it contains an actual playable stream.
  /// The caller retains the original response on any failure.
  Future<Map<String, dynamic>?> resolve({
    required Map<String, dynamic> identity,
    required Uri playUrl,
    required bool pgc,
    required Map<String, dynamic>? original,
  }) async {
    if (_closed) return null;
    final timer = Stopwatch()..start();
    try {
      final oldData = original == null ? null : playableData(original);
      final requestedQuality = int.tryParse(playUrl.queryParameters['qn'] ?? '');
      if (oldData != null && requestedQuality != null &&
          highestQuality(oldData) >= requestedQuality) {
        _status('原接口画质已满足目标，已跳过高画质服务');
        return null;
      }
      if (!await _initialize(identity) || _closed) return null;
      _status('正在请求高画质视频流');
      final response = await _post(pgc ? '/api/bzview3' : '/api/bzview2', {
        'ui': identity,
        'url': playUrl.toString(),
        if (pgc) 'iic': original?['code'] != 0,
        if (pgc) 'body': null,
      });
      if (_closed) return null;
      if (response?['code'] != 0) {
        _status(response?['code'] == 9
            ? '高画质服务配额不足，已使用原播放接口'
            : '高画质请求失败，已使用原播放接口');
        return null;
      }
      final result = playableData(response!);
      if (result == null) {
        _status('服务未返回可播放的高画质流，已使用原播放接口');
        return null;
      }
      if (oldData != null && highestQuality(result) <= highestQuality(oldData)) {
        _status('原接口画质已满足要求，继续使用原视频流');
        return null;
      }
      final quality = VideoQuality.fromCode(highestQuality(result)).desc;
      _status('高画质请求成功 · $quality · ${timer.elapsedMilliseconds} ms');
      return result;
    } on DioException catch (error) {
      if (!CancelToken.isCancel(error)) {
        _status('高画质服务连接失败或超时，已使用原播放接口');
      }
      return null;
    } catch (_) {
      // Never retain exception text: it can contain the request body or URL.
      _status('高画质响应格式无效，已使用原播放接口');
      return null;
    }
  }

  static const qualities = {6, 16, 32, 64, 74, 80, 112, 116, 120, 125, 126, 127, 129};

  static bool _mediaUrl(Object? value) {
    if (value is! String) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        const ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static int highestQuality(Map<String, dynamic> data) {
    final dash = data['dash'];
    final videos = dash is Map ? dash['video'] : null;
    if (videos is List) {
      return videos.whereType<Map>().fold<int>(0, (highest, video) {
        final id = video['id'];
        return id is int && id > highest ? id : highest;
      });
    }
    return data['quality'] is int ? data['quality'] as int : 0;
  }

  static Map<String, dynamic>? playableData(Map<String, dynamic> response) {
    Object? value = response['result'] ?? response['data'];
    if (value is Map && value['video_info'] is Map) value = value['video_info'];
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    if (!qualities.contains(data['quality'])) return null;
    final dash = data['dash'];
    if (dash is Map && dash['video'] is List) {
      final videos = (dash['video'] as List).whereType<Map>().where((video) {
        return qualities.contains(video['id']) &&
            _mediaUrl(video['baseUrl'] ?? video['base_url']);
      }).toList();
      if (videos.isEmpty || !videos.any((v) => v['id'] == data['quality'])) return null;
      videos.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      data['dash'] = {...dash, 'video': videos};
      // UI choices must come from returned streams, not a claimed capability list.
      data['accept_quality'] = videos.map((v) => v['id']).toSet().toList();
      final formats = data['support_formats'];
      if (formats is! List || formats.isEmpty) return null;
      return data;
    }
    final durl = data['durl'];
    if (durl is List && durl.isNotEmpty &&
        durl.every((item) => item is Map && _mediaUrl(item['url']))) {
      return data;
    }
    return null;
  }
}
