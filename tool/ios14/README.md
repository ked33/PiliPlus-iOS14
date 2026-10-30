# PiliPlus 2.1.6 / iPadOS 14.7 兼容构建

应用源码基于官方 `2.1.6.2` 标签，提交 `b2d6a5befb6dd292b9f7ad98794f3620f6dfb818`，即发行包 `2.1.6+5472`。
保留 Flutter 3.47.7 / Dart 3.13，重建同一修订的 Flutter 引擎；不把应用降级为 2.1.0。

官方引擎已将最低 iOS 版本提高到 15，并删除了部分旧系统分支。
`patch_flutter.py` 同时恢复刷新率、窗口访问、URL 归因的兼容处理，并调整引擎、CocoaPods、Dart AOT 和原生资源的构建目标。
已有 IPA 中的版本号不能代替这些源码更改和重新编译。

## 云构建

先运行 **Build Flutter engine for iOS 14**。它使用 Xcode 26.2 编译 iOS release 引擎及匹配的 macOS 主机工具，产出可复用的引擎 artifact。
引擎编译由 GitHub Actions 完成，Windows 无法执行此步骤。

当前适配需通过云端编译和 iPadOS 14.7 真机验证；最低系统版本检查并不等于运行时兼容性证明。

上游参考：
- https://github.com/flutter/flutter/pull/188187
- https://github.com/flutter/flutter/pull/188189
- https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2618

项目沿用上游 GPL-3.0 许可证。原作者和完整许可证见仓库根目录。
