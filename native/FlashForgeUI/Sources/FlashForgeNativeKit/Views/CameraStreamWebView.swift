import SwiftUI
import WebKit

#if os(macOS)
public struct CameraStreamWebView: NSViewRepresentable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else {
            return
        }
        webView.load(URLRequest(url: url))
    }
}
#else
public struct CameraStreamWebView: UIViewRepresentable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else {
            return
        }
        webView.load(URLRequest(url: url))
    }
}
#endif
