// AppDelegate.swift
// 与 Android MainActivity.kt 对齐的宿主生命周期：
//   - 注册 `verifin/app` MethodChannel（MainActivity.configureFlutterEngine 等价）；
//   - 快速记账 App Shortcut → openQuickEntry（QuickEntryTileService 等价）；
//   - 小组件深链 verifin://widget/... → openWidgetRoute（Glance widgetUri 等价）；
//   - 分享采集由 ShareExtension 写入 App Group，Dart 侧主动 consume。

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let quickEntryType = "top.talyra42.verifin.quickEntry"

  private var channelHandler: AppChannelHandler?
  private var pendingShortcut: UIApplicationShortcutItem?
  private var pendingUrl: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 快速记账 Shortcut 冷启动：先登记意图再走常规启动；
    // 返回 false 表示本进程已处理该 Shortcut，系统不再重复派发。
    let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem
    let shortcutHandled = shortcut.map { $0.type == Self.quickEntryType } ?? false
    pendingShortcut = shortcutHandled ? shortcut : nil
    pendingUrl = launchOptions?[.url] as? URL

    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    attachChannel()
    return shortcutHandled ? false : launched
  }

  /// 主 storyboard 在 didFinishLaunching 返回之后才挂上 window，
  /// 所以首次 attach 有可能取不到 FlutterViewController。若就此放弃，
  /// 通道会**静默缺失**（备份、小组件、导出全部失效且不报错），
  /// 因此这里用 didBecomeActive 兜底重试，保证最迟在首帧前后完成注册。
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    attachChannel()
  }

  private func attachChannel() {
    guard channelHandler == nil,
          let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let handler = AppChannelHandler(viewController: controller)
    channelHandler = handler
    // 冷启动携带的意图要等通道就绪后再补发，否则在 attach 前就被丢弃。
    if let shortcut = pendingShortcut {
      _ = handler.handleShortcutItem(shortcut)
      pendingShortcut = nil
    }
    if let url = pendingUrl {
      _ = handler.handleWidgetUrl(url)
      pendingUrl = nil
    }
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    attachChannel()
    guard let handler = channelHandler, handler.handleShortcutItem(shortcutItem) else {
      completionHandler(false)
      return
    }
    completionHandler(true)
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    attachChannel()
    if let handler = channelHandler, handler.handleWidgetUrl(url) {
      return true
    }
    return super.application(application, open: url, options: options)
  }
}
