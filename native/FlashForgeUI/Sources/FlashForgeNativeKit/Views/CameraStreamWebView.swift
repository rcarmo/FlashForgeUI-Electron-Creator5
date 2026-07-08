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
        guard context.coordinator.url != url else {
            return
        }
        context.coordinator.url = url
        webView.loadHTMLString(Self.html(for: url), baseURL: url.deletingLastPathComponent())
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        var url: URL?
    }

    private static func html(for url: URL) -> String {
        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              background: transparent;
              overflow: hidden;
            }
            img {
              width: 100vw;
              height: 100vh;
              object-fit: contain;
              display: block;
            }
          </style>
        </head>
        <body>
          <img src="\(escapedURL)" alt="">
        </body>
        </html>
        """
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
        guard context.coordinator.url != url else {
            return
        }
        context.coordinator.url = url
        webView.loadHTMLString(Self.html(for: url), baseURL: url.deletingLastPathComponent())
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        var url: URL?
    }

    private static func html(for url: URL) -> String {
        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              background: transparent;
              overflow: hidden;
            }
            img {
              width: 100vw;
              height: 100vh;
              object-fit: contain;
              display: block;
            }
          </style>
        </head>
        <body>
          <img src="\(escapedURL)" alt="">
        </body>
        </html>
        """
    }
}
#endif
