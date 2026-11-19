// AppChannel.swift
// `verifin/app` MethodChannel 的 iOS 端实现——与 Android MainActivity.kt +
// WidgetPreviewBridge.kt 的通道行为一一对应（等价移植，见 docs/ios-port.md）。
//
// 与 Android 的差异（iOS 平台边界内的等价方案）：
//   - setSecureFlag：iOS 无全局禁截屏 API，接受调用但为 no-op；
//   - 下载目录导出：iOS 没有公共 Downloads，改为暂存文件并弹出系统分享面板
//     （「存储到文件」等）；返回 true 表示已交给用户处理；
//   - 备份目录：SAF → UIDocumentPicker + 安全作用域书签；
//   - renderWidgetPreview：Glance 预览图 → 共享 SwiftUI 组合经 ImageRenderer 渲染 PNG
//     （iOS 16+；更低版本返回 null，Dart 侧显示「预览暂不可用」）；
//   - widgetInstanceCounts：WidgetKit 查询不到实例数，恒返回空。

import Flutter
import SwiftUI
import UIKit
import CryptoKit
import UniformTypeIdentifiers

/// 备份目录/文件 URI 的令牌 scheme：
///   目录 = `vfbk://<token>`；文件 = `vfbk://<dirToken>@file/<name>`
/// Dart 侧把 uri 原样保存并在后续调用传回，本文件负责解析。
private let bookmarkScheme = "vfbk"

final class AppChannelHandler {
    private let channel: FlutterMethodChannel
    private weak var viewController: FlutterViewController?

    // 一次性入站意图（与 Android 同规则：取走即清）。
    var pendingQuickEntryIntent = false
    private var pendingWidgetRoute: [String: String]?

    private let maxCaptureTextLength = 8_000
    private let maxCaptureImageBytes = 25 * 1024 * 1024
    private let sharePrefix = "verifin.share.pending"

    init(viewController: FlutterViewController) {
        self.viewController = viewController
        channel = FlutterMethodChannel(
            name: "verifin/app",
            binaryMessenger: viewController.binaryMessenger,
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    // MARK: - 入站（原生 → Flutter），与 Android onNewIntent 等价

    /// 快速记账 App Shortcut（应用长按图标菜单）到达。
    @discardableResult
    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard shortcutItem.type == "top.talyra42.verifin.quickEntry" else { return false }
        pendingQuickEntryIntent = true
        channel.invokeMethod("openQuickEntry", arguments: nil)
        return true
    }

    /// 小组件深链 `verifin://widget/<kind>/<route>?bookId=...` 到达。
    @discardableResult
    func handleWidgetUrl(_ url: URL) -> Bool {
        guard url.scheme == "verifin", url.host == "widget" else { return false }
        let segments = url.pathComponents.filter { $0 != "/" }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let bookId = components?.queryItems?.first(where: { $0.name == "bookId" })?.value ?? ""
        // iOS 无实例 id：kind → 模板序号，与 Dart `iosWidgetIdForKind` 对齐。
        var route = segments.count >= 2 ? segments[1] : "app"
        if route == "open" { route = "app" }
        if route == "quick_entry" { route = "entry" }
        let widgetId = segments.first.flatMap { VeriFinWidgetTemplate.fromKind($0)?.configId } ?? 0
        let map: [String: String] = [
            "route": route,
            "bookId": bookId,
            "widgetId": String(widgetId),
        ]
        pendingWidgetRoute = map
        channel.invokeMethod("openWidgetRoute", arguments: map)
        return true
    }

    // MARK: - 分享采集（ShareExtension 写入 App Group，应用在此消费）

    private func consumeCaptureImage(result: @escaping FlutterResult) {
        guard let defaults = UserDefaults(suiteName: VeriFinWidgetStore.appGroupId) else {
            result(nil); return
        }
        guard defaults.bool(forKey: sharePrefix + "Image") else { result(nil); return }
        defaults.removeObject(forKey: sharePrefix + "Image")
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: VeriFinWidgetStore.appGroupId)
        let file = container?.appendingPathComponent(sharePrefix + "Image.bin")
        guard let file, FileManager.default.fileExists(atPath: file.path) else {
            result(nil); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { try? FileManager.default.removeItem(at: file) }
            guard let self,
                  let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                  !data.isEmpty, data.count <= self.maxCaptureImageBytes
            else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
        }
    }

    private func consumeCaptureText(result: @escaping FlutterResult) {
        guard let defaults = UserDefaults(suiteName: VeriFinWidgetStore.appGroupId) else {
            result(nil); return
        }
        let text = defaults.string(forKey: sharePrefix + "Text")
        if text != nil { defaults.removeObject(forKey: sharePrefix + "Text") }
        result(text.map { String($0.prefix(maxCaptureTextLength)) })
    }

    // MARK: - MethodChannel 分发（方法名与 Android 完全一致）

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "consumeQuickEntryIntent":
            let shouldOpen = pendingQuickEntryIntent
            pendingQuickEntryIntent = false
            result(shouldOpen)
        case "consumeWidgetRoute":
            let route = pendingWidgetRoute
            pendingWidgetRoute = nil
            result(route)
        case "consumeCaptureImage":
            consumeCaptureImage(result: result)
        case "consumeCaptureText":
            consumeCaptureText(result: result)
        case "setSecureFlag":
            // iOS 无全局禁截屏 API：接受调用但不产生效果（与 Dart 侧容错语义一致）。
            result(true)
        case "saveTextToDownloads":
            exportToShareSheet(
                data: (args["content"] as? String ?? "").data(using: .utf8) ?? Data(),
                filename: args["filename"] as? String ?? "verifin-backup.json",
                result: result,
            )
        case "saveBytesToDownloads":
            let typed = args["bytes"] as? FlutterStandardTypedData
            exportToShareSheet(
                data: typed?.data ?? Data(),
                filename: args["filename"] as? String ?? "verifin-backup.zip",
                result: result,
            )
        case "saveCacheFileToDownloads":
            guard let path = args["cachePath"] as? String, !path.isEmpty else {
                result(nil); return
            }
            exportFileToShareSheet(path: path, result: result)
        case "pickBackupDirectory":
            pickBackupDirectory(result: result)
        case "pickBackupFile":
            pickBackupFile(result: result)
        case "stageBackupFile":
            stageBackupFile(args["fileUri"] as? String ?? "", result: result)
        case "writeBackupFromCache":
            writeBackupFromCache(args, result: result)
        case "listBackupFiles":
            listBackupFiles(args["directoryUri"] as? String ?? "", result: result)
        case "deleteBackupFile":
            deleteBackupFile(args["fileUri"] as? String ?? "", result: result)
        case "deleteCacheFile":
            deleteCacheFile(args["path"] as? String ?? "", result: result)
        case "availableBytes":
            result(availableBytes(args["path"] as? String ?? ""))
        case "renderWidgetPreview":
            renderWidgetPreview(args, result: result)
        case "widgetInstanceCounts":
            result([String: Int]())
        case "openApp":
            result(nil)
        case "refreshWidgetInstance":
            result(nil)
        case "widgetConfigurationInfo":
            // iOS 配置页不经此方法（Dart 侧 iOS 分支从深链解析模板），与 Android 保持同名即可。
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func fail(_ result: @escaping FlutterResult, _ code: String, _ message: String) {
        result(FlutterError(code: code, message: message, details: nil))
    }

    // MARK: - 导出（分享面板等价「下载目录」）

    private func exportToShareSheet(data: Data, filename: String, result: @escaping FlutterResult) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verifin-export-\(UUID().uuidString)")
            .appendingPathExtension((filename as NSString).pathExtension)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            fail(result, "EXPORT_FAILED", "导出失败，请稍后再试。")
            return
        }
        // 分享面板里显示用户可读的原始文件名。
        let named = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: named)
        try? FileManager.default.moveItem(at: url, to: named)
        presentShareSheet(for: named, result: result)
    }

    private func exportFileToShareSheet(path: String, result: @escaping FlutterResult) {
        let source = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            fail(result, "EXPORT_FAILED", "导出失败，请稍后再试。")
            return
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(source.lastPathComponent)
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            fail(result, "EXPORT_FAILED", error.localizedDescription)
            return
        }
        presentShareSheet(for: target, result: result)
    }

    private func presentShareSheet(for url: URL, result: @escaping FlutterResult) {
        guard let viewController else { result(false); return }
        DispatchQueue.main.async {
            let activity = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil,
            )
            activity.popoverPresentationController?.sourceView = viewController.view
            viewController.present(activity, animated: true)
            result(true)
        }
    }

    // MARK: - 备份目录（UIDocumentPicker + 书签）

    private func pickBackupDirectory(result: @escaping FlutterResult) {
        guard let viewController else {
            fail(result, "PICK_FAILED", "无法打开目录选择器。"); return
        }
        DispatchQueue.main.async {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.folder], asCopy: false,
            )
            picker.allowsMultipleSelection = false
            let delegate = DocumentPickerDelegate { [weak self] url in
                self?.finishDirectoryPick(url, result: result)
            }
            objc_setAssociatedObject(picker, &AssociatedKeys.pickDelegate, delegate, .OBJC_ASSOCIATION_RETAIN)
            picker.delegate = delegate
            viewController.present(picker, animated: true)
        }
    }

    private func finishDirectoryPick(_ url: URL?, result: @escaping FlutterResult) {
        guard let url else { result(nil); return }
        do {
            let token = UUID().uuidString
            let bookmark = try url.bookmarkData()
            guard let defaults = UserDefaults(suiteName: VeriFinWidgetStore.appGroupId) else {
                fail(result, "PICK_FAILED", "无法保存目录授权。"); return
            }
            defaults.set(bookmark, forKey: "verifin.bookmark.\(token)")
            result(["uri": "\(bookmarkScheme)://\(token)", "label": url.lastPathComponent])
        } catch {
            fail(result, "PICK_FAILED", error.localizedDescription)
        }
    }

    /// 书签令牌 → 安全作用域目录 URL；`body` 在访问权有效期内于后台线程执行，
    /// 参数为 (目录 URL, 目录令牌)，返回值/异常统一回主线程交付
    /// （与 Android 的 Thread + runOnUiThread 等价）。
    private func withDirectory(
        _ uri: String,
        _ result: @escaping FlutterResult,
        failureCode: String = "BACKUP_FAILED",
        _ body: @escaping (URL, String) throws -> Any?,
    ) {
        guard let defaults = UserDefaults(suiteName: VeriFinWidgetStore.appGroupId) else {
            fail(result, failureCode, "备份目录不可用，请重新选择。"); return
        }
        let token = uri.hasPrefix("\(bookmarkScheme)://")
            ? String(uri.dropFirst("\(bookmarkScheme)://".count).split(separator: "@").first ?? "")
            : ""
        guard !token.isEmpty, let data = defaults.data(forKey: "verifin.bookmark.\(token)") else {
            fail(result, failureCode, "备份目录不可用，请重新选择。"); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
                DispatchQueue.main.async {
                    self.fail(result, failureCode, "备份目录不可用，请重新选择。")
                }
                return
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let value = try body(url, token)
                DispatchQueue.main.async { result(value) }
            } catch {
                DispatchQueue.main.async {
                    self.fail(result, failureCode, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 备份文件选择（单文件；asCopy 让系统复制进应用 tmp，读权完整）

    private func pickBackupFile(result: @escaping FlutterResult) {
        guard let viewController else {
            fail(result, "PICK_FAILED", "无法打开文件选择器。"); return
        }
        DispatchQueue.main.async {
            var types: [UTType] = [.zip, .json]
            if let verifin = UTType(filenameExtension: "verifin") {
                types.append(verifin)
            }
            types.append(.data) // 兼容把 .verifin 当成未知类型的第三方文件管理器。
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = DocumentPickerDelegate { url in
                guard let url else { result(nil); return }
                let name = url.lastPathComponent
                let size = Self.fileSize(url)
                result(["uri": "vfstage://\(name)", "name": name, "size": size])
            }
            objc_setAssociatedObject(picker, &AssociatedKeys.pickDelegate, delegate, .OBJC_ASSOCIATION_RETAIN)
            picker.delegate = delegate
            viewController.present(picker, animated: true)
        }
    }

    private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
    }

    private func stageBackupFile(_ fileUri: String, result: @escaping FlutterResult) {
        if fileUri.isEmpty {
            fail(result, "BACKUP_READ_FAILED", "无法读取备份文件。"); return
        }
        if fileUri.hasPrefix("vfstage://") {
            // UIDocumentPicker asCopy=true 会把文件复制进应用沙盒（Documents/Inbox），
            // 按文件名在 Inbox / Documents / tmp 里查找最新一份。
            let name = String(fileUri.dropFirst("vfstage://".count))
            let directories = [
                FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Inbox"),
                FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
                FileManager.default.temporaryDirectory,
            ]
            let file = directories
                .map { $0.appendingPathComponent(name) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            guard let file else {
                fail(result, "BACKUP_READ_FAILED", "无法读取备份文件。"); return
            }
            result(["path": file.path, "bytes": Self.fileSize(file), "owned": true])
            return
        }
        // 兼容本地路径 / file://（与 Android 同行为：已是本地文件则不复制）。
        let path = fileUri.hasPrefix("file://")
            ? String(fileUri.dropFirst("file://".count))
            : fileUri
        let file = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            fail(result, "BACKUP_READ_FAILED", "无法读取备份文件。"); return
        }
        result(["path": file.path, "bytes": Self.fileSize(file), "owned": false])
    }

    // MARK: - 备份目录内容

    private func listBackupFiles(_ directoryUri: String, result: @escaping FlutterResult) {
        withDirectory(directoryUri, result) { directory, token in
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            )
            return try files.filter { file in
                let name = file.lastPathComponent
                return name.hasSuffix(".json") || name.hasSuffix(".zip") || name.hasSuffix(".verifin")
            }.map { file -> [String: Any] in
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return [
                    "uri": "\(bookmarkScheme)://\(token)@file/\(file.lastPathComponent)",
                    "name": file.lastPathComponent,
                    "modifiedAt": ((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000),
                    "sizeBytes": values?.fileSize ?? 0,
                ]
            }
        }
    }

    private func deleteBackupFile(_ fileUri: String, result: @escaping FlutterResult) {
        // uri 形如 vfbk://<dirToken>@file/<name>：解析出目录令牌与文件名。
        guard fileUri.hasPrefix("\(bookmarkScheme)://") else { result(false); return }
        let payload = String(fileUri.dropFirst("\(bookmarkScheme)://".count))
        guard
            let separator = payload.range(of: "@file/"),
            separator.lowerBound > payload.startIndex
        else { result(false); return }
        let dirToken = String(payload[payload.startIndex..<separator.lowerBound])
        let name = String(payload[separator.upperBound...])
        withDirectory("\(bookmarkScheme)://\(dirToken)", result) { directory, _ in
            let file = directory.appendingPathComponent(name)
            try FileManager.default.removeItem(at: file)
            return true
        }
    }

    private func writeBackupFromCache(_ args: [String: Any], result: @escaping FlutterResult) {
        let directoryUri = args["directoryUri"] as? String ?? ""
        let filename = args["filename"] as? String ?? "verifin-backup.zip"
        let cachePath = args["cachePath"] as? String ?? ""
        withDirectory(directoryUri, result) { directory, token in
            let target = directory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            FileManager.default.createFile(atPath: target.path, contents: nil)
            guard
                let input = FileHandle(forReadingAtPath: cachePath),
                let output = FileHandle(forWritingAtPath: target.path)
            else {
                throw NSError(domain: "VeriFinBackup", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "无法写入备份文件。"])
            }
            defer {
                try? output.close()
                try? input.close()
            }
            var digest = SHA256()
            var bytes = 0
            while true {
                let chunk = input.readData(ofLength: 64 * 1024)
                if chunk.isEmpty { break }
                try output.write(contentsOf: chunk)
                digest.update(data: chunk)
                bytes += chunk.count
            }
            let hex = digest.finalize().map { String(format: "%02x", $0) }.joined()
            return [
                "uri": "\(bookmarkScheme)://\(token)@file/\(filename)",
                "sha256": hex,
                "bytes": bytes,
            ] as [String: Any]
        }
    }

    private func deleteCacheFile(_ path: String, result: @escaping FlutterResult) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let target = URL(fileURLWithPath: path).standardized
        let inside = target.path == caches.path || target.path.hasPrefix(caches.path + "/")
        guard inside else { result(false); return }
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            result(true)
        } catch {
            result(false)
        }
    }

    private func availableBytes(_ path: String) -> Int? {
        let url = path.isEmpty
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : URL(fileURLWithPath: path)
        guard
            let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        else { return nil }
        let capacity = values.volumeAvailableCapacityForImportantUsage ?? 0
        return capacity > 0 ? Int(capacity) : 0
    }

    // MARK: - 小组件预览（Glance 预览 → ImageRenderer）

    private func renderWidgetPreview(_ args: [String: Any], result: @escaping FlutterResult) {
        guard
            #available(iOS 16.0, *),
            let templateKey = args["template"] as? String,
            let template = VeriFinWidgetTemplate(rawValue: templateKey)
        else { result(nil); return }
        let width = CGFloat((args["widthDp"] as? Int) ?? 168)
        let height = CGFloat((args["heightDp"] as? Int) ?? 168)
        let bookId = args["bookId"] as? String ?? ""
        let appearance = VeriFinWidgetAppearance.fromKey(args["appearance"] as? String)
        let sample = (args["sample"] as? Bool) ?? false
        let isDark = viewController?.traitCollection.userInterfaceStyle == .dark
        let selection = VeriFinWidgetSelection(bookId: bookId, appearance: appearance)
        let display = VeriFinWidgetStore.display(
            template: template,
            selection: selection,
            sample: sample,
            defaults: sample ? nil : VeriFinWidgetStore.defaults,
            isDark: isDark,
        )
        let view = VeriFinWidgetContentView(template: template, display: display)
            .frame(width: width, height: height)
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                let renderer = ImageRenderer(content: view)
                renderer.scale = UIScreen.main.scale
                if let data = renderer.uiImage?.pngData() {
                    result(FlutterStandardTypedData(bytes: data))
                } else {
                    result(nil)
                }
            } else {
                // iOS 15.x 无 ImageRenderer，按约定返回 null（Dart 侧显示「预览暂不可用」）。
                result(nil)
            }
        }
    }
}

// MARK: - 文件选择器代理（临时对象，闭包回传结果）

private struct AssociatedKeys {
    static var pickDelegate: UInt8 = 0
}

final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void
    init(completion: @escaping (URL?) -> Void) { self.completion = completion }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
