// ShareViewController.swift
// iOS 分享入口（与 Android ShareReceiverActivity.kt 等价）：接收系统分享的
// 图片/文本，写入 App Group 共享存储，等待主应用启动或回前台时消费。
//
// 等价映射：
//   ShareReceiverActivity.ACTION_CAPTURE_IMAGE → verifin.share.pendingImage (+ flag)
//   ShareReceiverActivity.ACTION_CAPTURE_TEXT  → verifin.share.pendingText
// 外部送入的文本不可信：长度上限在主应用消费侧截断（与 Android MAX_CAPTURE_TEXT_LENGTH
// 同值 8000），图片大小上限 25MB 同样在消费侧执行。

import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let appGroupId = "group.top.talyra42.verifin"
    private let textKey = "verifin.share.pendingText"
    private let imageFlagKey = "verifin.share.pendingImage"
    private let imageFileKey = "verifin.share.pendingImage.bin"

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let group = DispatchGroup()
        var savedAny = false

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                        defer { group.leave() }
                        guard let self, let data, !data.isEmpty, data.count <= 25 * 1024 * 1024 else { return }
                        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupId) {
                            let file = container.appendingPathComponent(self.imageFileKey)
                            do {
                                try data.write(to: file, options: .atomic)
                                defaults.set(true, forKey: self.imageFlagKey)
                                savedAny = true
                            } catch { /* 尽力而为：写不进就丢弃 */ }
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self else { return }
                        let text: String?
                        if let s = item as? String {
                            text = s
                        } else if let url = item as? URL {
                            text = url.absoluteString
                        } else {
                            text = nil
                        }
                        if let text, !text.isEmpty {
                            defaults.set(text, forKey: self.textKey)
                            savedAny = true
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            _ = savedAny
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
