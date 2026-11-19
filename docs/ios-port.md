# iOS 移植说明（v1.21.1 → IPA）

本仓库在 v1.21.1 的 Android-only 基础上完成了 **iOS 端等价实现**：核心记账功能 100% 复用同一套 Dart 代码，Android 深度集成的原生能力用 Swift 逐一重写。本文档说明等价映射、iOS 端的折衷差异与打包签名流程。

## 构建要求

| 项 | 要求 |
|---|---|
| Flutter | 3.50.0 stable（Dart 3.14，满足 pubspec `sdk: ^3.12.2`） |
| Xcode | 15.3+（建议 16.x），iOS 15.5 部署目标（ML Kit 要求 ≥15.5） |
| Apple 账号 | 侧载：免费 Apple ID 即可；TestFlight/App Store：开发者账号（$99/年） |

## 快速开始

```bash
flutter pub get
flutter build ios --release --no-codesign   # 未签名 .app（build/ios/iphoneos/Runner.app）
# 或（需要签名配置）：
flutter build ipa --release
```

CI 打包：见 `.github/workflows/ios-build.yml`（macOS Runner，自动产出未签名 IPA 构件）。

**侧载安装（个人 Apple ID，7 天有效期，最多 3 台设备）**：下载 CI 产出的未签名 IPA，用 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/) 输入 Apple ID 重签安装。扩展（小组件/分享）会随主包一起签名。

**正式分发**：在 Secrets 配置证书后使用 workflow 中注释掉的签名构建步骤，导出签名 IPA 上 TestFlight / App Store。

## 等价映射（Android → iOS）

| Android 实现 | iOS 等价实现 | 文件 |
|---|---|---|
| `MainActivity.kt` 的 `verifin/app` MethodChannel | `AppChannel.swift`（同名通道、同方法名） | `ios/Runner/AppChannel.swift` |
| Glance 小组件 ×4（`VeriFinWidget.kt`） | WidgetKit ×4（kind = `verifin_<template.key>`） | `ios/VeriFinWidgets/` + `ios/Runner/VeriFinWidgetStore.swift`、`VeriFinWidgetViews.swift` |
| `ShareReceiverActivity` 分享采集 | Share Extension → App Group → 主应用消费 | `ios/ShareExtension/ShareViewController.swift` |
| `QuickEntryTileService` 快捷磁贴 | 应用长按图标 App Shortcut（快速记账） | `AppDelegate.swift` |
| SAF 备份目录/文件 | UIDocumentPicker + 安全作用域书签（`vfbk://` 令牌 URI） | `AppChannel.swift` |
| MediaStore 下载目录导出 | 系统分享面板「存储到文件」（iOS 无公共 Downloads） | `AppChannel.swift` |
| FLAG_SECURE 防截屏 | 无系统级 API，接受调用但 no-op（iOS 平台限制） | `AppChannel.swift` |
| WidgetConfigurationActivity | 主应用内打开 `WidgetConfigurationPage`（深链 route=setup） | `lib/pages/shell.dart` |
| Glance 预览图（PNG） | 共享 SwiftUI 组合 + ImageRenderer（iOS 16+；更低版本返回 null） | `AppChannel.swift` |
| 午夜刷新闹钟 | WidgetKit Timeline 的午夜 TimelineEntry + `.atEnd` | `VeriFinWidgets.swift` |

## 数据契约（与 Android 完全一致）

- 共享存储键：`verifin.widget.snapshots` / `.books` / `.locale` / `verifin.widget.config.<id>`（快照 `version` = 2）。
- 深链：`verifin://widget/<kind>/<route>?bookId=...`（route: `app` / `entry` / `setup` / `assets` / `reports` / `profile`）。
- App Group：`group.top.talyra42.verifin`（Runner、小组件、分享扩展三者共享）。
- iOS 实例 id：kind → 模板序号 1..4（Dart `iosWidgetIdForKind` 与 Swift `configId` 同规则）。

## iOS 端已知折衷（平台边界）

1. **小组件实例配置按 kind 共享**：同一种模板的多个桌面实例共用一份账本选择（WidgetKit 无 per-instance id）；单实例场景与 Android 行为一致。未配置时若只有一本账会自动选用，减少配置摩擦。
2. **防截屏**：iOS 应用无法全局禁用截屏/录屏；应用锁（PIN + 生物识别）功能完整。
3. **「记一笔」热区**：iOS 小组件是单点击目标——快速记账横条整条点击进入记账页（Android 横条内另有独立按钮）。
4. **导出**：写入「文件」App 需经系统分享面板确认（Android 直接写 MediaStore）。
5. **小组件刷新**：由 WidgetKit 预算调度（应用内数据推送后 `WidgetCenter.reloadTimelines` 请求刷新），不保证秒级。
6. **快捷磁贴**：iOS 无磁贴概念，等价为应用长按图标菜单的「快速记账」。

## Dart 侧改动清单（保持 Android 行为不变）

- `lib/app/backup/backup_storage_io.dart`：桥接启用条件 `isAndroid` → `isAndroid || isIOS`（9 处）。
- `lib/app/widgets/widget_service.dart`：iOS 统一推送全模板、`updateWidget(iOSName: kind)`。
- `lib/app/widgets/widget_instance_config.dart`：iOS 深链解析 kind 的配置会话；保存后 `updateWidget` 刷新。
- `lib/pages/shell.dart`：route=setup 在 iOS 上主应用内打开配置页。
- `lib/main.dart`：启动时 `HomeWidget.setAppGroupId('group.top.talyra42.verifin')`。

## 工程注入脚本

`scripts/inject_ios_targets.py` 幂等注入（重复运行会跳过）两个扩展 target 到 `Runner.xcodeproj`。若用 `flutter create` 重新生成 iOS 工程，需重跑一次。

## 打包与签名安装

| 文件 | 作用 |
|---|---|
| `scripts/prepare_sideload_ipa.py` | 把 `flutter build ios --no-codesign` 的产物打成可重签 IPA。`--mode full` 保留两个扩展；`--mode lite` 删除扩展，使任何证书都能签。产物 `build/ios/ipa/verifin-{mode}.ipa`。 |
| `.github/workflows/ios-build.yml` | macOS runner 自动构建并产出两个 IPA artifact，无需本地 Mac。 |
| `docs/sign-with-quannengqian.md` | 全能签签名安装的逐项设置、自检清单与报错对照表。 |

```bash
# 本地出包（Mac）
flutter build ios --release --no-codesign
python3 scripts/prepare_sideload_ipa.py --app build/ios/iphoneos/Runner.app --mode lite
```

`lite` 与 `full` 的选择标准只有一个：签名用的描述文件里有没有 `App Groups`。没有就只能用 lite（小组件与分享扩展随之不可用，其余功能完整）。

