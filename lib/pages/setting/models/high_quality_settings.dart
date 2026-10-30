import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/services/high_quality_client.dart';
import 'package:PiliPlus/services/high_quality_playback.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get highQualitySettings => [
  NormalModel(
    title: '高画质播放（实验性）',
    getSubtitle: () => HighQualityPlayback.enabled ? '已开启 · 请求失败时使用原视频流' : '已关闭',
    leading: const Icon(Icons.high_quality_outlined),
    getTrailing: (_) => Icon(HighQualityPlayback.enabled ? Icons.toggle_on : Icons.toggle_off_outlined),
    onTap: (context, refresh) async {
      final enable = !HighQualityPlayback.enabled;
      if (enable && !await _confirm(context, HighQualityPlayback.server)) return;
      await GStorage.setting.put(HighQualityPlayback.enabledKey, enable);
      HighQualityPlayback.reset();
      refresh();
    },
  ),
  NormalModel(
    title: '高画质服务地址',
    getSubtitle: () => HighQualityPlayback.server,
    leading: const Icon(Icons.dns_outlined),
    onTap: (context, refresh) async {
      final controller = TextEditingController(text: HighQualityPlayback.server);
      String? error;
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => AlertDialog(
          title: const Text('高画质服务地址'),
          content: TextField(
            controller: controller, keyboardType: TextInputType.url,
            autocorrect: false, enableSuggestions: false,
            decoration: InputDecoration(hintText: 'https://example.com', errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            TextButton(onPressed: () {
              final uri = HighQualityClient.parseServer(controller.text);
              if (uri == null) {
                setState(() => error = '请输入 HTTP/HTTPS 地址，不含账号、查询参数或片段');
              } else {
                Navigator.pop(dialogContext, uri.toString());
              }
            }, child: const Text('保存')),
          ],
        )),
      );
      controller.dispose();
      if (value == null || !context.mounted) return;
      if (HighQualityPlayback.enabled && !await _confirm(context, value)) return;
      await GStorage.setting.put(HighQualityPlayback.serverKey, value);
      HighQualityPlayback.reset();
      refresh();
    },
  ),
  NormalModel(
    title: '高画质目标画质',
    getSubtitle: () => VideoQuality.fromCode(HighQualityPlayback.targetQuality).desc,
    leading: const Icon(Icons.video_settings_outlined),
    onTap: (context, refresh) async {
      final quality = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('高画质目标画质'),
          children: [for (final quality in VideoQuality.values.where((q) => q.code >= 80))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, quality.code),
              child: Text(quality.desc),
            ),
          ],
        ),
      );
      if (quality == null) return;
      await GStorage.setting.put(HighQualityPlayback.qualityKey, quality);
      HighQualityPlayback.reset();
      refresh();
    },
  ),
  NormalModel(
    title: '高画质请求状态',
    subtitle: '查看最近一次请求结果',
    leading: const Icon(Icons.monitor_heart_outlined),
    onTap: (context, _) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('高画质请求状态'),
        content: ValueListenableBuilder<String>(
          valueListenable: HighQualityPlayback.status,
          builder: (_, value, _) => Text(value),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    ),
  ),
  NormalModel(
    title: '高画质所用账号',
    getSubtitle: () => HighQualityPlayback.accountLabel,
    leading: const Icon(Icons.account_circle_outlined),
    onTap: (context, refresh) async {
      final values = <int, String>{
        0: '跟随当前视频账号', -1: '使用主账号',
        for (final account in Accounts.account.values) account.mid: 'UID ${account.mid}',
      };
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('高画质所用账号'),
          children: [for (final entry in values.entries) SimpleDialogOption(
            onPressed: () => Navigator.pop(context, entry.key),
            child: Text('${entry.key == HighQualityPlayback.accountId ? "✓ " : ""}${entry.value}'),
          )],
        ),
      );
      if (selected == null) return;
      await GStorage.setting.put(HighQualityPlayback.accountKey, selected);
      HighQualityPlayback.reset();
      refresh();
    },
  ),
];

Future<bool> _confirm(BuildContext context, String server) => showConfirmDialog(
  context: context,
  title: const Text('启用高画质服务？'),
  content: Text('将向 $server 发送所选账号的登录 Cookie、UID 和当前视频信息。'
      '服务端能够使用这些登录凭证。'
      '${Uri.tryParse(server)?.scheme == "http" ? "此地址使用 HTTP，凭证将明文传输。" : ""}'
      '\n\n仅在信任该服务时启用。请求状态不会保存登录凭证。'),
);
