#!/usr/bin/env python3
"""Backport iOS 14 support to the exact Flutter SDK used by release 5472.

The engine must be rebuilt after this patch. Editing an existing IPA is not
sufficient. Keep the Dart VM and the AOT compiler at the same revision.
"""

import argparse
from pathlib import Path
import subprocess

FLUTTER_REVISION = "abaf9c523780a608bd46686fd5e53740a07077f8"


def patch(root: Path, tools_only: bool = False) -> None:
    revision = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != FLUTTER_REVISION:
        raise SystemExit(f"Expected Flutter 3.47.7 ({FLUTTER_REVISION}), got {revision}")

    edits = {
        "engine/src/build/config/darwin/darwin_sdk.gni": [
            ('ios_deployment_target = "15.0"', 'ios_deployment_target = "14.0"'),
        ],
        "packages/flutter_tools/lib/src/darwin/darwin.dart": [
            ("ios => Version(15, 0, null)", "ios => Version(14, 0, null)"),
        ],
        "packages/flutter_tools/lib/src/isolated/native_assets/ios/native_assets.dart": [
            ("const targetIOSVersion = 15;", "const targetIOSVersion = 14;"),
        ],
        "packages/flutter_tools/bin/podhelper.rb": [
            ("s.ios.deployment_target = '15.0'", "s.ios.deployment_target = '14.0'"),
        ],
        "packages/flutter_tools/lib/src/ios/migrations/ios_deployment_target_migration.dart": [
            ("Updating minimum iOS deployment target to 15.0.",
             "Updating minimum iOS deployment target to 14.0."),
            ("const deploymentTargetReplacement = 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;';",
             "const deploymentTargetReplacement = 'IPHONEOS_DEPLOYMENT_TARGET = 14.0;';"),
            ('''const podfilePlatformVersionReplacement = "platform :ios, '15.0'";''',
             '''const podfilePlatformVersionReplacement = "platform :ios, '14.0'";'''),
        ],
        "engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterMetalLayer.mm": [
            ("""  _displayLink.preferredFrameRateRange =
      CAFrameRateRangeMake(forceMax ? maxFrameRate : minFrameRate, maxFrameRate, maxFrameRate);""",
             """  if (@available(iOS 15.0, *)) {
    _displayLink.preferredFrameRateRange =
        CAFrameRateRangeMake(forceMax ? maxFrameRate : minFrameRate, maxFrameRate, maxFrameRate);
  } else {
    _displayLink.preferredFramesPerSecond = maxFrameRate;
  }"""),
        ],
        "engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformPlugin.mm": [
            ("""      rootViewController =
          [engineViewController flutterWindowSceneIfViewLoaded].keyWindow.rootViewController;""",
             """      UIWindowScene* scene = [engineViewController flutterWindowSceneIfViewLoaded];
      for (UIWindow* window in scene.windows) {
        if (window.isKeyWindow) {
          rootViewController = window.rootViewController;
          break;
        }
      }"""),
        ],
        "engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTextInputPlugin.mm": [
            ("""  _cachedFirstResponder =
      flutterApplication
          ? flutterApplication.keyWindow.flutterFirstResponder
          : self.viewController.flutterWindowSceneIfViewLoaded.keyWindow.flutterFirstResponder;""",
             """  UIWindow* keyWindow = flutterApplication.keyWindow;
  if (!flutterApplication) {
    for (UIWindow* window in self.viewController.flutterWindowSceneIfViewLoaded.windows) {
      if (window.isKeyWindow) {
        keyWindow = window;
        break;
      }
    }
  }
  _cachedFirstResponder = keyWindow.flutterFirstResponder;"""),
        ],
        "engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPluginAppLifeCycleDelegate.mm": [
            ("""  if (options.eventAttribution) {
    convertedOptions[UIApplicationOpenURLOptionsEventAttributionKey] = options.eventAttribution;
  }""",
             """  if (@available(iOS 14.5, *)) {
    if (options.eventAttribution) {
      convertedOptions[UIApplicationOpenURLOptionsEventAttributionKey] = options.eventAttribution;
    }
  }"""),
        ],
    }

    # Validate every edit before writing anything; fail if upstream source drifts.
    pending = {}
    for name, replacements in edits.items():
        if tools_only and not name.startswith("packages/flutter_tools/"):
            continue
        path = root / name
        original = path.read_bytes()
        content = original
        for before, after in replacements:
            old, new = before.encode(), after.encode()
            if new in content and old not in content:
                continue
            if content.count(old) != 1:
                raise SystemExit(f"Expected exactly one patch anchor in {name}: {before[:70]}")
            content = content.replace(old, new, 1)
        if content != original:
            pending[path] = content
    for path, content in pending.items():
        path.write_bytes(content)
        print(path.relative_to(root))
    if any("packages/flutter_tools/" in str(path.as_posix()) for path in pending):
        # Flutter's downloaded CLI snapshot otherwise still enforces iOS 15.
        for name in ("flutter_tools.snapshot", "flutter_tools.stamp"):
            (root / "bin/cache" / name).unlink(missing_ok=True)
    print(f"iOS 14 source patch ready; updated {len(pending)} files")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("flutter_root", type=Path)
    parser.add_argument("--tools-only", action="store_true")
    args = parser.parse_args()
    patch(args.flutter_root.resolve(), args.tools_only)
