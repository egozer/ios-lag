import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var game: WKWebView!
    private var sharing = false

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: "lag")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(self, name: "shareScore")
        config.userContentController.add(self, name: "haptic")
        config.userContentController.add(self, name: "openSettings")
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let payload = try! JSONSerialization.data(withJSONObject: ["locale": language])
        let localeJSON = String(data: payload, encoding: .utf8)!
        config.userContentController.addUserScript(WKUserScript(source: "window.LAGNative = Object.freeze(\(localeJSON));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #if DEBUG
        config.userContentController.add(self, name: "diagnostics")
        config.userContentController.addUserScript(WKUserScript(source: "window.addEventListener('error', e => window.webkit.messageHandlers.diagnostics.postMessage({ error: String(e.message || e.target?.src || e.target?.href || 'Asset failed') }), true); window.addEventListener('unhandledrejection', e => window.webkit.messageHandlers.diagnostics.postMessage({ error: String(e.reason) }));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif
        game = WKWebView(frame: .zero, configuration: config)
        game.navigationDelegate = self
        game.isOpaque = false
        game.backgroundColor = UIColor(red: 16/255, green: 17/255, blue: 20/255, alpha: 1)
        game.scrollView.backgroundColor = game.backgroundColor
        game.scrollView.contentInsetAdjustmentBehavior = .never
        game.scrollView.bounces = false
        #if DEBUG
        game.isInspectable = true
        #endif
        view = game
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        game.load(URLRequest(url: URL(string: "lag://app/index.html")!))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        decisionHandler(url?.scheme == "lag" && url?.host == "app" ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        #if DEBUG
        if message.name == "diagnostics" {
            NSLog("LAG diagnostics: %@", String(describing: message.body)); return
        }
        #endif
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "lag",
              message.frameInfo.securityOrigin.host == "app",
              let body = message.body as? [String: Any] else { return }
        if message.name == "openSettings" {
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settings)
            }
            return
        }
        if message.name == "haptic" {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred((body["correct"] as? Bool ?? true) ? .success : .error)
            return
        }
        guard message.name == "shareScore",
              let requestID = body["requestId"] as? String,
              let text = body["text"] as? String, text.count <= 1000,
              let encoded = body["image"] as? String, encoded.count < 8_000_000 else { return }
        guard !sharing, presentedViewController == nil,
              let bytes = Data(base64Encoded: encoded),
              let image = UIImage(data: bytes) else {
            completeShare(requestID, status: "failed"); return
        }
        sharing = true
        let sheet = UIActivityViewController(activityItems: [text, image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = game
        sheet.popoverPresentationController?.sourceRect = CGRect(x: game.bounds.midX, y: game.bounds.maxY - 40, width: 1, height: 1)
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, error in
            self?.sharing = false
            self?.completeShare(requestID, status: error == nil ? (completed ? "shared" : "cancelled") : "failed")
        }
        present(sheet, animated: true)
    }

    private func completeShare(_ requestID: String, status: String) {
        game.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('lag-share-complete', { detail: payload }));", arguments: ["payload": ["requestId": requestID, "status": status]], in: nil, in: .page, completionHandler: nil)
    }
}
