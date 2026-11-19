// VeriFinWidgetViews.swift
// 与 Android 端 VeriFinWidgetContent（Glance 组合）等价的 SwiftUI 渲染。
// 本文件同时编译进 Runner（应用内 ImageRenderer 预览）与 VeriFinWidgets 扩展。
// 色彩 token 与 lib/app/app_theme.dart / Android 原生一致。

import SwiftUI

enum VeriFinWidgetPalette {
    static let royal = Color(red: 0x34 / 255.0, green: 0x6E / 255.0, blue: 0xDB / 255.0)
    static let textLight = Color(red: 0x11 / 255.0, green: 0x18 / 255.0, blue: 0x27 / 255.0)
    static let textDark = Color(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0)
    static let mutedLight = Color(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0)
    static let mutedDark = Color(red: 0xB8 / 255.0, green: 0xC0 / 255.0, blue: 0xCC / 255.0)
    static let trackLight = Color(red: 0xE5 / 255.0, green: 0xE7 / 255.0, blue: 0xEB / 255.0)
    static let trackDark = Color(red: 0x30 / 255.0, green: 0x35 / 255.0, blue: 0x3D / 255.0)
}

/// 预算进度环（对应 Kotlin `WidgetGraphics.ring`）。
struct VeriFinBudgetRing: View {
    let usage: Double
    let dark: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(dark ? VeriFinWidgetPalette.trackDark : VeriFinWidgetPalette.trackLight,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(usage, 0), 1)))
                .stroke(VeriFinWidgetPalette.royal,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((min(max(usage, 0), 1) * 100).rounded()))%")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(dark ? .white : VeriFinWidgetPalette.textLight)
        }
    }
}

/// 支出趋势线（对应 Kotlin `WidgetGraphics.sparkline`：面积填充 + 描边）。
struct VeriFinSparkline: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let linePoints = normalizedPoints(in: size)
            ZStack {
                if linePoints.count >= 2 {
                    Path { path in
                        path.move(to: linePoints[0])
                        for point in linePoints.dropFirst() { path.addLine(to: point) }
                    }
                    .fill(VeriFinWidgetPalette.royal.opacity(0.125))
                    Path { path in
                        path.move(to: linePoints[0])
                        for point in linePoints.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(VeriFinWidgetPalette.royal,
                            style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard points.count >= 2, size.width > 0, size.height > 0 else { return [] }
        var low = points.min() ?? 0
        var high = points.max() ?? 1
        if high - low < 0.0001 { low -= 1; high += 1 }
        let count = max(points.count - 1, 1)
        return points.enumerated().map { index, value in
            let x = CGFloat(index) * size.width / CGFloat(count)
            let y = size.height - (CGFloat((value - low) / (high - low)) * (size.height - 4) + 2)
            return CGPoint(x: x, y: y)
        }
    }
}

/// 与 Android 同一套组合：选择器预览、生成预览与应用内草稿预览共用。
struct VeriFinWidgetContentView: View {
    let template: VeriFinWidgetTemplate
    let display: VeriFinWidgetDisplay
    var compactQuickEntry: Bool = true

    var body: some View {
        let foreground = display.dark ? VeriFinWidgetPalette.textDark : VeriFinWidgetPalette.textLight
        let muted = display.dark ? VeriFinWidgetPalette.mutedDark : VeriFinWidgetPalette.mutedLight
        Group {
            if display.state != .ready {
                // 未配置 / 无数据：只显示一句话，不给任何金额，也不猜一个默认账本。
                Text(display.label)
                    .font(.system(size: 13))
                    .foregroundColor(foreground)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if template == .quickEntry {
                quickEntryBody(foreground: foreground, muted: muted)
            } else {
                metricBody(foreground: foreground, muted: muted)
            }
        }
    }

    /// 快速记账横条（对应 Kotlin `QuickWidgetContent`：左侧数据 + 右侧记一笔）。
    @ViewBuilder
    private func quickEntryBody(foreground: Color, muted: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.label)
                    .font(.system(size: 11))
                    .foregroundColor(muted)
                    .lineLimit(1)
                Text(display.amount)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            Text(VeriFinWidgetStore.localizedLabel(
                "quick_entry_button",
                chinese: VeriFinWidgetStore.isChinese(VeriFinWidgetStore.defaults),
            ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(VeriFinWidgetPalette.royal))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func metricBody(foreground: Color, muted: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(display.label)
                .font(.system(size: 11))
                .foregroundColor(muted)
                .lineLimit(1)
            if template == .trend {
                HStack(alignment: .bottom, spacing: 10) {
                    Text(display.amount)
                        .font(.system(size: display.amount.count > 12 ? 18 : 24, weight: .bold))
                        .foregroundColor(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if display.points.count >= 2 {
                        VeriFinSparkline(points: display.points)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Spacer(minLength: 0)
                Text(display.amount)
                    .font(.system(size: display.amount.count > 12 ? 18 : 24, weight: .bold))
                    .foregroundColor(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if template == .budget, let usage = display.usage {
                    HStack {
                        Spacer()
                        VeriFinBudgetRing(usage: usage, dark: display.dark)
                            .frame(width: 52, height: 52)
                            .padding(.bottom, 2)
                    }
                }
                if template == .netWorth, display.points.count >= 2 {
                    VeriFinSparkline(points: display.points)
                        .frame(height: 40)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
