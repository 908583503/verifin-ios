// VeriFinWidgetStore.swift
// 与 Android 端 VeriFinWidget.kt（Kotlin/Glance）等价的数据层。
// 本文件同时编译进 Runner（应用内预览渲染）与 VeriFinWidgets（WidgetKit 扩展），
// 与 Dart 侧 widget_service.dart 的共享存储键保持同一契约。
//
// 共享存储键（与 lib/app/widgets/widget_instance_config.dart 对齐）：
//   verifin.widget.snapshots / verifin.widget.books / verifin.widget.locale
//   verifin.widget.config.<实例 id>   （Android=appWidgetId，iOS=模板序号 1..4）

import Foundation
import UIKit

/// 投影快照的结构版本。**必须与 Dart 侧的 `widgetSnapshotVersion` 成对修改**。
let veriFinSnapshotVersion = 2

/// 四个固定模板（与 Dart `WidgetTemplate` / Kotlin `VeriFinWidgetTemplate` 对齐）。
enum VeriFinWidgetTemplate: String, CaseIterable {
    case quickEntry = "quick_entry"
    case budget = "budget"
    case trend = "trend"
    case netWorth = "net_worth"

    /// iOS WidgetKit kind（与 Dart 侧 `verifin_<template.key>` 一致）。
    var kind: String { "verifin_\(rawValue)" }

    /// 配置页使用的数字实例 id（Dart `iosWidgetIdForKind` 同规则：模板序号，1 起）。
    var configId: Int {
        (VeriFinWidgetTemplate.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static func fromKind(_ kind: String) -> VeriFinWidgetTemplate? {
        let key = kind.hasPrefix("verifin_") ? String(kind.dropFirst("verifin_".count)) : kind
        return VeriFinWidgetTemplate(rawValue: key)
    }

    var metricLabelKey: String {
        switch self {
        case .quickEntry: return "widget_today_expense"
        case .budget: return "widget_budget_remaining"
        case .trend: return "widget_trend_period_expense"
        case .netWorth: return "widget_net_worth"
        }
    }

    var displayNameKey: String {
        switch self {
        case .quickEntry: return "widget_template_quick_entry"
        case .budget: return "widget_template_budget"
        case .trend: return "widget_trend_period_expense"
        case .netWorth: return "widget_net_worth"
        }
    }

    var displayName: String {
        switch self {
        case .quickEntry: return "快速记账"
        case .budget: return "预算进度"
        case .trend: return "收支趋势"
        case .netWorth: return "净资产"
        }
    }
}

/// 实例外观众。默认跟随系统（与 Dart `WidgetAppearance` 对齐）。
enum VeriFinWidgetAppearance: String {
    case system, light, dark

    static func fromKey(_ key: String?) -> VeriFinWidgetAppearance {
        VeriFinWidgetAppearance(rawValue: key ?? "") ?? .system
    }
}

/// 一个桌面实例的设备本地配置：账本必选，外观可选。
struct VeriFinWidgetSelection {
    var bookId: String = ""
    var appearance: VeriFinWidgetAppearance = .system
}

/// 组件当前该渲染什么。
enum VeriFinWidgetContentState {
    case needsSetup   // 还没配置（或配置里的账本已不存在）
    case needsSync    // 已配置但还没拿到该账本的数据
    case ready        // 正常渲染指标
}

/// 组件渲染数据（与 Kotlin `WidgetDisplay` 对齐）。
struct VeriFinWidgetDisplay {
    var state: VeriFinWidgetContentState
    var label: String
    var amount: String = ""
    var points: [Double] = []
    var usage: Double? = nil
    var dark: Bool = false
    var bookId: String = ""
}

/// 共享存储（App Group UserDefaults）。Runner 与 WidgetKit 扩展共用同一份。
enum VeriFinWidgetStore {
    static let appGroupId = "group.top.talyra42.verifin"
    static let configPrefix = "verifin.widget.config."

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// 读取某个实例的配置；未配置或不可解析时返回空选择（账本为空 = 未配置）。
    static func config(_ defaults: UserDefaults?, id: Int) -> VeriFinWidgetSelection {
        guard let raw = defaults?.string(forKey: "\(configPrefix)\(id)") else {
            return VeriFinWidgetSelection()
        }
        guard let json = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return VeriFinWidgetSelection()
        }
        let bookId = object["bookId"] as? String ?? ""
        if bookId.isEmpty { return VeriFinWidgetSelection() }
        return VeriFinWidgetSelection(
            bookId: bookId,
            appearance: .fromKey(object["appearance"] as? String),
        )
    }

    /// 桌面上显示的文字跟随**应用语言**（与 Android `localized` 一致）。
    static func isChinese(_ defaults: UserDefaults?) -> Bool {
        let language = defaults?.string(forKey: "verifin.widget.locale") ?? ""
        if language.isEmpty { return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false }
        return language.lowercased().hasPrefix("zh")
    }

    static func localizedLabel(_ key: String, chinese: Bool) -> String {
        let table: [String: (String, String)] = [
            "widget_template_quick_entry": ("快速记账", "Quick entry"),
            "widget_template_budget": ("预算进度", "Budget progress"),
            "widget_template_trend": ("收支趋势", "Cash flow trend"),
            "widget_template_net_worth": ("净资产", "Net worth"),
            "quick_entry_button": ("记一笔", "Add entry"),
            "widget_today_expense": ("今日支出", "Today's spending"),
            "widget_budget_remaining": ("剩余预算", "Budget remaining"),
            "widget_trend_period_expense": ("近 30 日支出", "Last 30 days"),
            "widget_setup_required": ("点击进入配置", "Tap to set up"),
            "widget_data_unavailable": ("打开应用同步数据", "Open the app to sync"),
        ]
        let pair = table[key] ?? (key, key)
        return chinese ? pair.0 : pair.1
    }

    /// 把「实例配置 + 投影快照」解析成可渲染的数据（与 Kotlin `display` 等价）。
    /// `sample` 是选择器 / 预览用的样例态：只给零值，绝不读用户账目。
    static func display(
        template: VeriFinWidgetTemplate,
        selection: VeriFinWidgetSelection,
        sample: Bool = false,
        now: Date = Date(),
        defaults: UserDefaults? = defaults,
        isDark: Bool = UITraitCollection.current.userInterfaceStyle == .dark,
    ) -> VeriFinWidgetDisplay {
        let chinese = isChinese(defaults)
        let dark: Bool
        switch selection.appearance {
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = isDark
        }
        let label = localizedLabel(template.metricLabelKey, chinese: chinese)
        if sample {
            return VeriFinWidgetDisplay(
                state: .ready, label: label, amount: "0",
                points: Array(repeating: 0, count: 30),
                usage: template == .budget ? 0 : nil, dark: dark,
            )
        }
        if selection.bookId.isEmpty {
            return VeriFinWidgetDisplay(
                state: .needsSetup,
                label: localizedLabel("widget_setup_required", chinese: chinese),
                dark: dark,
            )
        }
        guard
            let root = readSnapshots(defaults),
            let version = root["version"] as? Int, version == veriFinSnapshotVersion,
            let snapshot = root[selection.bookId] as? [String: Any]
        else {
            return VeriFinWidgetDisplay(
                state: .needsSync,
                label: localizedLabel("widget_data_unavailable", chinese: chinese),
                dark: dark, bookId: selection.bookId,
            )
        }
        let item = snapshot[template.rawValue] as? [String: Any]
        // 「今日支出」跨天后直接归零：桌面不必等用户打开应用。
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expiredToday = template == .quickEntry
            && (snapshot["date"] as? String) != formatter.string(from: now)
        let amount: String
        if expiredToday {
            amount = "0"
        } else {
            let raw = item?["amount"] as? String ?? ""
            amount = raw.isEmpty ? "—" : raw
        }
        var points: [Double] = []
        if let rawPoints = item?["points"] as? [Any] {
            let values = rawPoints.compactMap { $0 as? Double ?? ($0 as? NSNumber)?.doubleValue }
            if values.count == rawPoints.count && values.allSatisfy({ $0.isFinite }) {
                points = values
            }
        }
        let usageRaw = (item?["usage"] as? Double) ?? ((item?["usage"] as? NSNumber)?.doubleValue ?? Double.nan)
        let usage = usageRaw.isFinite ? usageRaw : nil
        return VeriFinWidgetDisplay(
            state: .ready, label: label, amount: amount,
            points: points, usage: usage, dark: dark, bookId: selection.bookId,
        )
    }

    private static func readSnapshots(_ defaults: UserDefaults?) -> [String: Any]? {
        guard
            let raw = defaults?.string(forKey: "verifin.widget.snapshots"),
            let data = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
