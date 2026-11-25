import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_catalog.dart';

/// home_widget 共享存储中与小组件相关的键。全部是**设备本地**数据，不进备份。
const String widgetSnapshotsKey = 'verifin.widget.snapshots';
const String widgetBooksKey = 'verifin.widget.books';
const String widgetLocaleKey = 'verifin.widget.locale';
const String widgetConfigPrefix = 'verifin.widget.config.';

/// iOS 小组件 kind 前缀：WidgetKit 的 kind 必须与 `HomeWidget.updateWidget`
/// 的 `iOSName` 一致。实例配置按 kind 存（同 kind 的多个实例共享一份配置——
/// WidgetKit 无实例 id 概念，属于 iOS 端的等价折衷，见 docs/ios-port.md）。
const String iosWidgetKindPrefix = 'verifin_';

/// iOS kind → 配置页使用的数字 id。Android 用 `appWidgetId` 隔离实例；iOS
/// 没有 id，改用模板序号（1 起）。Swift 端按同一规则读取。
int iosWidgetIdForKind(String kind) {
  final key = kind.startsWith(iosWidgetKindPrefix)
      ? kind.substring(iosWidgetKindPrefix.length)
      : kind;
  final index = WidgetTemplate.values.indexWhere(
    (template) => template.key == key,
  );
  return index >= 0 ? index + 1 : 0;
}

/// 单个桌面实例的配置：账本必选，外观可选（默认跟随系统）。
///
/// 实例配置按 Android `appWidgetId` 隔离，只存在设备原生共享存储中；备份、导出与
/// 换机都不会带走它，删除实例时由原生 Receiver 清理。
class WidgetInstanceConfig {
  const WidgetInstanceConfig({required this.bookId, required this.appearance});

  final String bookId;
  final WidgetAppearance appearance;

  static WidgetInstanceConfig? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final bookId = decoded['bookId'];
      if (bookId is! String || bookId.isEmpty) return null;
      return WidgetInstanceConfig(
        bookId: bookId,
        appearance: WidgetAppearance.fromKey(decoded['appearance'] as String?),
      );
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode(<String, Object?>{
    'bookId': bookId,
    'appearance': appearance.key,
  });
}

/// 读取可用账本（`id` → 名称），供配置页选择；应用尚未推送过数据时为空。
Future<Map<String, String>> readWidgetBooks() async {
  final raw = await HomeWidget.getWidgetData<String>(
    widgetBooksKey,
    defaultValue: '[]',
  );
  final books = <String, String>{};
  for (final book in (jsonDecode(raw ?? '[]') as List).whereType<Map>()) {
    final id = book['id'];
    if (id is String && id.isNotEmpty) {
      books[id] = book['name']?.toString() ?? '';
    }
  }
  return books;
}

/// 读取某个实例已保存的配置；未配置（或配置不可解析）返回 `null`。
Future<WidgetInstanceConfig?> readWidgetInstanceConfig(int widgetId) async =>
    WidgetInstanceConfig.decode(
      await HomeWidget.getWidgetData<String>('$widgetConfigPrefix$widgetId'),
    );

/// 一次配置会话只服务一个桌面实例，**不构造 Controller、不读数据库**。
class WidgetSetupSession {
  const WidgetSetupSession({
    required this.widgetId,
    required this.template,
    required this.books,
    required this.config,
  });

  final int widgetId;
  final WidgetTemplate template;

  /// 可选账本（`id` → 名称）；空表示应用还没推送过账本，此时无法保存。
  final Map<String, String> books;

  /// 已保存的配置；`null` 表示这个实例还没配置过。
  final WidgetInstanceConfig? config;

  static const MethodChannel _channel = MethodChannel('verifin/app');

  static Future<WidgetSetupSession> load() async {
    if (Platform.isIOS) {
      // iOS：配置页经由 `verifin://widget/<kind>/setup` 深链打开，从启动 URL
      // 解析 kind（home_widget 把它作为 launch URL 交给 Dart）。
      final launch = await HomeWidget.initiallyLaunchedFromHomeWidget();
      final kind = _iosKindFromLaunchUri(launch);
      final template = WidgetTemplate.fromKey(
        kind.startsWith(iosWidgetKindPrefix)
            ? kind.substring(iosWidgetKindPrefix.length)
            : kind,
      );
      if (template == null) {
        throw StateError('Invalid widget instance');
      }
      return WidgetSetupSession(
        widgetId: iosWidgetIdForKind(kind),
        template: template,
        books: await readWidgetBooks(),
        config: await readWidgetInstanceConfig(iosWidgetIdForKind(kind)),
      );
    }
    final widgetId = int.tryParse(
      await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure() ?? '',
    );
    if (widgetId == null || widgetId <= 0) {
      throw StateError('Invalid widget instance');
    }
    final info = await _channel.invokeMapMethod<String, Object?>(
      'widgetConfigurationInfo',
      <String, Object?>{'widgetId': widgetId},
    );
    if (info == null) throw StateError('Widget metadata unavailable');
    final template = WidgetTemplate.fromKey(info['template'] as String?);
    if (template == null) throw StateError('Unknown widget template');
    return WidgetSetupSession(
      widgetId: widgetId,
      template: template,
      books: await readWidgetBooks(),
      config: await readWidgetInstanceConfig(widgetId),
    );
  }

  /// 从 `verifin://widget/<kind>/<route>` 解析小组件 kind；解析不出返回空串。
  static String _iosKindFromLaunchUri(Uri? uri) {
    if (uri == null || uri.scheme != 'verifin' || uri.authority != 'widget') {
      return '';
    }
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
  }

  /// 保存实例配置。写回后**重新读取校验**，再让原生立即重渲染该实例，
  /// 最后才向启动器确认配置完成——任一步失败都不谎报成功。
  Future<void> save(WidgetInstanceConfig config) async {
    if (!books.containsKey(config.bookId)) {
      throw StateError('Invalid widget book');
    }
    final key = '$widgetConfigPrefix$widgetId';
    final encoded = config.encode();
    if (await HomeWidget.saveWidgetData<String>(key, encoded) != true) {
      throw StateError('Widget preference write failed');
    }
    if (await HomeWidget.getWidgetData<String>(key) != encoded) {
      throw StateError('Widget preference verification failed');
    }
    if (Platform.isIOS) {
      // iOS：让 WidgetKit 立即重渲染该 kind 的时间线；无 Android 配置回执流程。
      final kind = '$iosWidgetKindPrefix${template.key}';
      if (await HomeWidget.updateWidget(iOSName: kind) != true) {
        throw StateError('Widget refresh failed');
      }
      return;
    }
    await _channel.invokeMethod<void>(
      'refreshWidgetInstance',
      <String, Object?>{'widgetId': widgetId},
    );
    await HomeWidget.finishHomeWidgetConfigure();
  }
}
