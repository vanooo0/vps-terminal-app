import SwiftUI
import WebKit

// Config.swift is generated at build time from the TERMINAL_URL secret.
let TERMINAL_URL = URL(string: terminalURLString)!

struct WebTerminal: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.backgroundColor = .black
        wv.isOpaque = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.load(URLRequest(url: TERMINAL_URL))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@main
struct VPSTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                WebTerminal()
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .statusBarHidden(false)
            .preferredColorScheme(.dark)
        }
    }
}
