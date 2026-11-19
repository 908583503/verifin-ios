// VeriFinWidgets.swift
// iOS 桌面小组件（WidgetKit）——与 Android Glance 四模板一一对应的等价实现。
// 数据读取 App Group 共享存储（与 Dart widget_service.dart / Kotlin VeriFinWidgetStore
// 同一套键），点击经 verifin://widget/<kind>/<route> 深链回到应用。

import WidgetKit
import SwiftUI

// 四个模板各一个 Widget（kind 与 Dart 侧 `verifin_<template.key>` 一致）：
//   verifin_quick_entry / verifin_budget / verifin_trend / verifin_net_worth

@main
struct VeriFinWidgetBundle: WidgetBundle {
    var body: some Widget {
        VeriFinQuickEntryWidget()
        VeriFinBudgetWidget()
        VeriFinTrendWidget()
        VeriFinNetWorthWidget()
    }
}

// MARK: - 时间线

struct VeriFinSnapshotEntry: TimelineEntry {
    let date: Date
    let display: VeriFinWidgetDisplay
    let template: VeriFinWidgetTemplate
}

struct VeriFinSnapshotProvider: TimelineProvider {
    let template: VeriFinWidgetTemplate

    func placeholder(in context: Context) -> VeriFinSnapshotEntry {
        entry(date: Date(), sample: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (VeriFinSnapshotEntry) -> Void) {
        completion(entry(date: Date(), sample: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VeriFinSnapshotEntry>) -> Void) {
        // 「今日支出」跨天归零：在下一个本地午夜排一个刷新点（等价 Android 端
        // scheduleWidgetUpdates 的午夜闹钟）；其余刷新由 WidgetKit 预算驱动。
        let entry = self.entry(date: Date(), sample: false)
        var dates = [entry.date]
        let calendar = Calendar.current
        if let nextMidnight = calendar.nextDate(
            after: entry.date, matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime,
        ) {
            dates.append(nextMidnight)
        }
        completion(Timeline(entries: dates.map { self.entry(date: $0, sample: false) }, policy: .atEnd))
    }

    private func entry(date: Date, sample: Bool) -> VeriFinSnapshotEntry {
        let defaults = VeriFinWidgetStore.defaults
        let selection: VeriFinWidgetSelection
        if sample {
            selection = VeriFinWidgetSelection()
        } else {
            let config = VeriFinWidgetStore.config(defaults, id: template.configId)
            // 未配置时回退到唯一账本（或第一本），减少「必须先进配置页」的摩擦；
            // 无任何账本数据时仍走 needsSetup / needsSync 提示，与 Android 一致。
            if config.bookId.isEmpty, !sample,
               let booksRaw = defaults?.string(forKey: "verifin.widget.books"),
               let data = booksRaw.data(using: .utf8),
               let books = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstId = books.compactMap({ $0["id"] as? String }).first,
               books.count == 1 {
                selection = VeriFinWidgetSelection(bookId: firstId, appearance: config.appearance)
            } else {
                selection = config
            }
        }
        let display = VeriFinWidgetStore.display(
            template: template,
            selection: selection,
            sample: sample,
            defaults: sample ? nil : defaults,
        )
        return VeriFinSnapshotEntry(date: date, display: display, template: template)
    }
}

// MARK: - 视图

struct VeriFinWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VeriFinSnapshotEntry

    var body: some View {
        let url = deepLink
        content
            .widgetURL(url)
            .modifier(VeriFinBackgroundModifier(dark: entry.display.dark))
    }

    /// 点击路由（对应 Kotlin widgetUri(id, route)）：
    /// 数据区 → app；快速记账横条整体 → app（横条内无独立按钮热区，
    /// iOS 单点击目标下「记一笔」由深链 entry 承担——见 docs/ios-port.md）；
    /// 未配置 → setup。
    private var deepLink: URL {
        let kind = entry.template.kind
        let bookId = entry.display.bookId
        let route: String
        switch entry.display.state {
        case .needsSetup: route = "setup"
        case .needsSync: route = "app"
        case .ready: route = entry.template == .quickEntry ? "entry" : "app"
        }
        return URL(string: "verifin://widget/\(kind)/\(route)?bookId=\(bookId)")!
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            VeriFinWidgetContentView(template: entry.template, display: entry.display)
                .containerBackground(for: .widget) { Color.clear }
        } else {
            VeriFinWidgetContentView(template: entry.template, display: entry.display)
                .padding(4)
        }
    }
}

/// 与 Android `widget_surface_light/dark` 一致的圆角卡片底。
struct VeriFinBackgroundModifier: ViewModifier {
    let dark: Bool

    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(dark
                        ? Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x26 / 255)
                        : Color.white),
            )
        } else {
            content.background(
                dark
                    ? Color(red: 0x1C / 255, green: 0x20 / 255, blue: 0x26 / 255)
                    : Color.white,
            )
        }
    }
}

// MARK: - 四个模板

struct VeriFinQuickEntryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VeriFinWidgetTemplate.quickEntry.kind,
                            provider: VeriFinSnapshotProvider(template: .quickEntry)) { entry in
            VeriFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("快速记账")
        .description("今日支出概览与快速记账入口")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VeriFinBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VeriFinWidgetTemplate.budget.kind,
                            provider: VeriFinSnapshotProvider(template: .budget)) { entry in
            VeriFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("预算进度")
        .description("本期可用预算概览")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VeriFinTrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VeriFinWidgetTemplate.trend.kind,
                            provider: VeriFinSnapshotProvider(template: .trend)) { entry in
            VeriFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("收支趋势")
        .description("近 30 日支出趋势")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct VeriFinNetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: VeriFinWidgetTemplate.netWorth.kind,
                            provider: VeriFinSnapshotProvider(template: .netWorth)) { entry in
            VeriFinWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("净资产")
        .description("全部账户资产总额")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
