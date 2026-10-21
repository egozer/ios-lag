import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serves only files shipped inside the app. No HTTP server or network fallback.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "lag", url.host == "app",
              let root = Bundle.main.url(forResource: "Web", withExtension: nil) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let relative = url.path == "/" ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/"),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let type: String
        switch file.pathExtension {
        case "js", "mjs": type = "application/javascript"
        case "css": type = "text/css"
        case "html": type = "text/html"
        default: type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type, "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*"])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Files are delivered synchronously; no outstanding task remains to cancel.
    }
}
