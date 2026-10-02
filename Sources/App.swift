import SwiftUI
import WebKit
import AVFoundation

// Config.swift is generated at build time from the TERMINAL_URL secret.
let TERMINAL_URL = URL(string: terminalURLString)!

// Keep-alive: iOS suspends a backgrounded web app within seconds, which drops the
// terminal's websocket. Playing looping silent audio (with the "audio" background
// mode) keeps the app running in the background, so the SSH session stays connected
// and the user never has to re-authenticate. No security tradeoff — the same
// already-authenticated connection is simply held open.
final class KeepAlive {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        do {
            let p = try AVAudioPlayer(data: KeepAlive.silentWav(seconds: 2))
            p.numberOfLoops = -1      // loop forever
            p.volume = 0.0            // inaudible (samples are silence anyway)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {}

        // Resume after interruptions (calls, other audio) and on foreground return.
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            try? session.setActive(true)
            self?.player?.play()
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            try? session.setActive(true)
            self?.player?.play()
        }
    }

    // Build a minimal silent PCM WAV in memory (no bundled asset needed).
    static func silentWav(seconds: Int) -> Data {
        let sampleRate = 8000, channels = 1, bits = 16
        let dataSize = sampleRate * seconds * channels * bits / 8
        var d = Data()
        func s(_ str: String) { d.append(str.data(using: .ascii)!) }
        func le32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func le16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        s("RIFF"); le32(36 + dataSize); s("WAVE")
        s("fmt "); le32(16); le16(1); le16(channels)
        le32(sampleRate); le32(sampleRate * channels * bits / 8); le16(channels * bits / 8); le16(bits)
        s("data"); le32(dataSize)
        d.append(Data(count: dataSize))   // silence
        return d
    }
}

let bgColor = Color(red: 0x0D/255, green: 0x11/255, blue: 0x17/255)
let amber = Color(red: 0xF0/255, green: 0xA3/255, blue: 0x5E/255)

// Состояние загрузки страницы: пока она грузится — своя заставка вместо чёрного экрана.
final class LoadState: ObservableObject {
    @Published var loaded = false
    @Published var failed = false
}

struct WebTerminal: UIViewRepresentable {
    @ObservedObject var state: LoadState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        // кнопка «Вставить» на странице: берём текст прямо из буфера айфона, без системных окошек
        cfg.userContentController.add(context.coordinator, name: "vpsPaste")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.backgroundColor = UIColor(red: 0x0D/255, green: 0x11/255, blue: 0x17/255, alpha: 1)
        wv.isOpaque = false
        wv.scrollView.bounces = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        context.coordinator.webView = wv
        wv.load(URLRequest(url: TERMINAL_URL))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let state: LoadState
        weak var webView: WKWebView?
        init(state: LoadState) {
            self.state = state
            super.init()
            NotificationCenter.default.addObserver(forName: .retryLoad, object: nil, queue: .main) { [weak self] _ in self?.retry() }
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "vpsPaste", let wv = webView else { return }
            let text = UIPasteboard.general.string ?? ""
            let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
            let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
            // ответ — в ту же рамку, откуда нажали (VPS или встроенное окно ПК2)
            wv.evaluateJavaScript("window.__nativePaste && window.__nativePaste(\(arr)[0])", in: message.frameInfo, in: .page) { _ in }
        }

        func retry() {
            state.failed = false
            webView?.load(URLRequest(url: TERMINAL_URL))
        }

        // Страница сама рисует такую же заставку первым куском — меняемся с ней незаметно.
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.state.loaded = true }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { state.failed = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.loaded = false
            state.failed = true
        }
        // Без этого iOS молча глушит окна страницы (подтверждения, ввод текста).
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(a) ?? completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "Да", style: .default) { _ in completionHandler(true) })
            present(a) ?? completionHandler(false)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            present(a) ?? completionHandler(nil)
        }
        private func present(_ vc: UIViewController) -> Void? {
            guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return nil }
            var top = root
            while let p = top.presentedViewController { top = p }
            top.present(vc, animated: true)
            return ()
        }
    }
}

struct Splash: View {
    let failed: Bool
    let retry: () -> Void
    @State private var x: CGFloat = -1

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(">_").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundColor(amber)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.2)).frame(width: 120, height: 3)
                    Capsule().fill(amber).frame(width: 48, height: 3).offset(x: x * 84 + 36)
                }
                .frame(width: 120, height: 3).clipped()
                .opacity(failed ? 0 : 1)
                Text(failed ? "нет связи с сервером — проверь Tailscale" : "загружаю…")
                    .font(.system(size: 15, weight: .medium)).foregroundColor(Color(white: 0.55))
                if failed {
                    Button("Повторить", action: retry)
                        .font(.system(size: 17, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(amber).cornerRadius(10)
                }
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { x = 1 } }
    }
}

struct RootView: View {
    @StateObject private var state = LoadState()

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            WebTerminal(state: state).ignoresSafeArea(.container, edges: .bottom)
            if !state.loaded || state.failed {
                Splash(failed: state.failed) {
                    NotificationCenter.default.post(name: .retryLoad, object: nil)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: state.loaded)
    }
}

extension Notification.Name { static let retryLoad = Notification.Name("retryLoad") }

@main
struct VPSTerminalApp: App {
    init() {
        KeepAlive.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .statusBarHidden(false)
                .preferredColorScheme(.dark)
        }
    }
}
