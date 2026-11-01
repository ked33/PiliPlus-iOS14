# PiliPlus 2.1.6 / iPadOS 14.7 兼容构建

应用源码基于官方 `2.1.6.2` 标签，提交 `b2d6a5befb6dd292b9f7ad98794f3620f6dfb818`，即发行包 `2.1.6+5472`。
保留 Flutter 3.47.7 / Dart 3.13，重建同一修订的 Flutter 引擎；不把应用降级为 2.1.0。

官方引擎已将最低 iOS 版本提高到 15，并删除了部分旧系统分支。
`patch_flutter.py` 同时恢复刷新率、窗口访问、URL 归因的兼容处理，并调整引擎、CocoaPods、Dart AOT 和原生资源的构建目标。
已有 IPA 中的版本号不能代替这些源码更改和重新编译。

## 云构建

运行唯一的 **Build IPA for iPadOS 14.7** 工作流。它先使用 Xcode 26.2 编译 iOS release 引擎及匹配的 macOS 主机工具，再构建应用。引擎会缓存复用；最终安装包位于 `PiliPlus-iOS14-IPA` artifact。
引擎编译由 GitHub Actions 完成，Windows 无法执行此步骤。

当前适配需通过云端编译和 iPadOS 14.7 真机验证；最低系统版本检查并不等于运行时兼容性证明。

### iPadOS 14.7.1 启动时 CoreMedia 符号缺失

曾出现 `DYLD, symbol '_CMTimebaseCreateWithSourceClock' not found`，在运行应用代码前就被系统终止。
`Runner` 的最低版本为 14.0 仍可能有此问题：现代 CoreMedia SDK 把这个重命名接口标注为 iOS 6，但旧系统实际导出的是 `CMTimebaseCreateWithMasterClock`。
Debug / Release 的 xcconfig 对 C 和 Swift 的 Clang importer 显式设置 `CMTIMEBASE_USE_SOURCE_TERMINOLOGY=0`，让 SDK 使用旧系统兼容分支；无需重编 Flutter 引擎。
`verify_ipa.py` 检查 Mach-O 未定义符号表，拒绝对已知缺失符号的强引用，并把 CoreMedia timebase 导入写入报告。这是针对已知崩溃的回归检查，不是完整的系统 API 兼容性扫描。

上游参考：
- https://github.com/flutter/flutter/pull/188187
- https://github.com/flutter/flutter/pull/188189
- https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2618

项目沿用上游 GPL-3.0 许可证。原作者和完整许可证见仓库根目录。

## 高画质播放

入口：设置 → 视频设置。提供「高画质播放（实验性）」「高画质服务地址」「高画质目标画质」「高画质请求状态」「高画质所用账号」。

接口协议按用户提供的 MIT userscript 0.0.6 实现：`/api/bzusta` 校验账号与配额，`/api/bzview2` 解析普通视频，`/api/bzview3` 对接番剧。
默认地址为脚本使用的服务地址，可以更改。请求超时、配额不足、服务协议变化、响应无法解析或没有更高画质时，保留原播放结果。原账号登录态和会员展示不作伪装。

该功能默认关闭。启用时会说明账号凭证外发和 HTTP 明文传输；只发送 SESSDATA、bili_jct、DedeUserID、buvid3 四项 Cookie。第三方请求禁用重定向、独立于官方账号拦截器，状态只保留固定消息和画质/耗时，不保存原始响应或登录凭证。客户端不会自动打开服务端返回的跳转链接。

协议测试使用模拟服务，未用用户真实 Cookie 请求第三方服务。PGC 与服务端的实际兼容性仍需真机验证；失败时回退。

目标画质默认 4K，可以调整；实际播放仍遵循播放器的默认画质偏好。原接口已提供目标画质时，直接跳过服务端账号校验和解析请求。
