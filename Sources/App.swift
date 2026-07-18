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
    init() {
        KeepAlive.shared.start()
    }

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
