import 'dart:convert';

import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/services/high_quality_client.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

abstract final class HighQualityPlayback {
  static const enabledKey = 'enableHighQualityPlayback';
  static const serverKey = 'highQualityPlaybackServer';
  static const accountKey = 'highQualityPlaybackAccount';
  static const defaultServer = 'http://mxd.indevs.in';
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const cookieNames = {'SESSDATA', 'bili_jct', 'DedeUserID', 'buvid3'};

  static bool get enabled => GStorage.setting.get(enabledKey, defaultValue: false);
  static String get server => GStorage.setting.get(serverKey, defaultValue: defaultServer);
  static int get accountId => GStorage.setting.get(accountKey, defaultValue: 0);
  static final status = ValueNotifier<String>('尚未请求高画质服务');

  static HighQualityClient? _client;
  static String? _identityKey;
  static Map<String, dynamic>? _identity;
  static DateTime? _identityUntil;
  static DateTime? _retryAt;
  static int _generation = 0;

  static Account? get selectedAccount {
    final id = accountId;
    if (id == 0) return Accounts.video;
    if (id == -1) return Accounts.main;
    for (final account in Accounts.account.values) {
      if (account.mid == id) return account;
    }
    return null;
  }

  static String get accountLabel {
    final account = selectedAccount;
    final label = accountId == 0 ? '当前视频账号' : accountId == -1 ? '主账号' : '指定账号';
    return '$label · ${account?.isLogin == true ? "UID ${account!.mid}" : "未登录"}';
  }

  static void reset() {
    _generation++;
    _client?.close();
    _client = null;
    _identityKey = null;
    _identity = null;
    _identityUntil = null;
    _retryAt = null;
    status.value = enabled ? '等待下一次播放请求' : '高画质播放已关闭';
  }

  static Future<Map<String, dynamic>?> enhance({
    required Map<String, dynamic> original,
    required Map<String, dynamic> parameters,
    required VideoType type,
  }) async {
    if (!enabled) return null;
    // Paid courses use a different protocol from the supplied userscript.
    if (type == VideoType.pugv) return null;
    final account = selectedAccount;
    final base = HighQualityClient.parseServer(server);
    if (account?.isLogin != true || base == null) {
      status.value = base == null ? '高画质服务地址无效' : '高画质账号未登录';
      return null;
    }
    final generation = _generation;
    final selected = account!;
    try {
      final cookies = await selected.cookieJar.loadForRequest(Uri.parse('https://api.bilibili.com/'));
      final picked = {for (final cookie in cookies) if (cookieNames.contains(cookie.name)) cookie.name: cookie.value};
      if ((picked['SESSDATA'] ?? '').isEmpty || picked['DedeUserID'] != '${selected.mid}') {
        status.value = '所选账号登录凭证不完整，已使用原播放接口';
        return null;
      }
      final cookie = picked.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
      final key = '$base:${selected.mid}:${sha256.convert(utf8.encode(cookie))}';
      if (generation != _generation || !enabled || selectedAccount != selected) return null;
      if (_identityKey != key) {
        _client?.close();
        _identityKey = key;
        _identity = null;
        _identityUntil = null;
        _retryAt = null;
        _client = HighQualityClient(
          server: base,
          dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
          onStatus: (message) { if (_identityKey == key && enabled) status.value = message; },
        );
      }
      if (_retryAt case final until? when until.isAfter(DateTime.now())) return null;
      if (_identity == null || _identityUntil!.isBefore(DateTime.now())) {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          followRedirects: false,
        ));
        try {
          // Validate this specific account with Bilibili before contacting the service.
          final response = await dio.get<Map<String, dynamic>>(
            'https://api.bilibili.com/x/web-interface/nav',
            options: Options(headers: {'Cookie': cookie, 'User-Agent': _userAgent, 'Referer': 'https://www.bilibili.com/'}),
          );
          final data = response.data?['data'];
          if (data is! Map || data['isLogin'] != true || '${data['mid']}' != '${selected.mid}') {
            status.value = '所选账号登录已失效，已使用原播放接口';
            _retryAt = DateTime.now().add(const Duration(seconds: 30));
            return null;
          }
          if (generation != _generation || _identityKey != key || selectedAccount != selected || !enabled) return null;
          _identity = {
            'ua': _userAgent, 'mid': '${selected.mid}',
            'vip': data['vipStatus'] == 0 ? 0 : 1,
            'level': data['level_info'] is Map ? data['level_info']['current_level'] : 0,
            'money': (data['money'] as num?)?.truncate() ?? 0,
            'cookie': cookie, 'csrf': picked['bili_jct'] ?? '',
          };
          _identityUntil = DateTime.now().add(const Duration(minutes: 15));
        } finally {
          dio.close(force: true);
        }
      }
      final clean = <String, String>{
        for (final name in ['avid', 'bvid', 'cid', 'qn', 'ep_id', 'season_id', 'fnval', 'fnver', 'fourk', 'voice_balance', 'cur_language'])
          if (parameters[name] != null) name: '${parameters[name]}',
      };
      final uri = Uri.https('api.bilibili.com', type == VideoType.pgc ? type.api : '/x/player/playurl', clean);
      final result = await _client!.resolve(identity: _identity!, playUrl: uri, pgc: type == VideoType.pgc, original: original);
      if (generation != _generation || _identityKey != key || !enabled || selectedAccount != selected) return null;
      if (result == null) _retryAt = DateTime.now().add(const Duration(seconds: 30));
      return result;
    } catch (_) {
      if (generation == _generation) status.value = '高画质请求失败，已使用原播放接口';
      return null;
    }
  }
}
