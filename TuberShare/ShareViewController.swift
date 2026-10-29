import UIKit
import UniformTypeIdentifiers

/// Takes a shared video link, hands it to the app via App Group and opens tuber://play.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handle() }
    }

    private func handle() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
        var id: String?
        for p in providers where id == nil {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                id = VideoLink.videoID(from: url)
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                id = VideoLink.videoID(fromText: text)
            }
        }
        if let id {
            UserDefaults(suiteName: Bundle.main.object(forInfoDictionaryKey: "TuberAppGroup") as? String)?.set(id, forKey: "pendingVideoID")
            openApp(URL(string: "tuber://play?v=\(id)")!)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Extensions can't call UIApplication.open directly; reach it through the responder chain.
    private func openApp(_ url: URL) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector), let imp = r.method(for: selector) {
                typealias Open = @convention(c) (AnyObject, Selector, URL, [String: Any], ((Bool) -> Void)?) -> Void
                unsafeBitCast(imp, to: Open.self)(r, selector, url, [:], nil)
                return
            }
            responder = r.next
        }
    }
}
