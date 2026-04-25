import SwiftUI
import WebKit
import Combine
import Foundation

// MARK: - メインビュー（ContentView）
struct ContentView: View {
    // --- 1. UserDefaultsによる永続保存（@AppStorage） ---
    @AppStorage("selectedUA") private var selectedUA: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"
    @AppStorage("proxyHost") private var proxyHost: String = ""
    @AppStorage("proxyPort") private var proxyPort: Int = 8080
    @AppStorage("lastURL") private var lastURL: String = "https://www.google.com"
    
    // --- 2. 内部状態管理 ---
    @State private var urlInput: String = ""
    @State private var isLoading: Bool = false
    @State private var estimatedProgress: Double = 0.0
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var refreshID = UUID() // 設定変更時にWebViewを完全に再構築するためのトリガー
    
    // --- 3. 5つの主要UAリスト (iOS 18.4.1 完全版) ---
    let uaOptions: [String: String] = [
        "Safari": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1",
        "Chrome": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/134.0.6998.92 Mobile/15E148 Safari/604.1",
        "Firefox": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/136.0 Mobile/15E148 Safari/604.1",
        "Edge": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 EdgiOS/134.0.3124.96 Mobile/15E148 Safari/604.1",
        "Opera": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OPiOS/10.0.0 Mobile/15E148 Safari/604.1"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // --- 上部：設定・アドレスバーパネル ---
            VStack(spacing: 12) {
                // UA切り替え（セグメント）
                Picker("User Agent", selection: $selectedUA) {
                    ForEach(uaOptions.keys.sorted(), id: \.self) { key in
                        Text(key).tag(uaOptions[key]!)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedUA) { _, _ in applySettings() }
                
                // プロキシ入力
                HStack {
                    Image(systemName: "network")
                    TextField("Proxy Host (IP)", text: $proxyHost)
                    TextField("Port", value: $proxyPort, formatter: NumberFormatter())
                        .frame(width: 70)
                    Button("適用") { applySettings() }
                        .buttonStyle(.borderedProminent)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                // アドレスバー
                HStack {
                    TextField("URLを入力", text: $urlInput, onCommit: { loadNewURL() })
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                    
                    Button(action: loadNewURL) {
                        Image(systemName: "arrow.right.circle.fill").font(.title)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            
            // プログレスバー
            if isLoading {
                ProgressView(value: estimatedProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 3)
            }

            // --- 中部：WebView本体 ---
            WebViewComponent(
                url: URL(string: lastURL)!,
                ua: selectedUA,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                isLoading: $isLoading,
                progress: $estimatedProgress,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward
            )
            .id(refreshID) // これを更新することでWebViewを物理的に再生成し、UA/プロキシを確実に適用する
            
            // --- 下部：ナビゲーションツールバー ---
            HStack {
                Button(action: { NotificationCenter.default.post(name: .goBack, object: nil) }) {
                    Image(systemName: "chevron.backward").font(.title2)
                }.disabled(!canGoBack)
                
                Spacer()
                
                Button(action: { applySettings() }) {
                    Image(systemName: "arrow.clockwise").font(.title2)
                }
                
                Spacer()
                
                Button(action: { NotificationCenter.default.post(name: .goForward, object: nil) }) {
                    Image(systemName: "chevron.forward").font(.title2)
                }.disabled(!canGoForward)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 15)
            .background(Color(.secondarySystemBackground))
        }
        .onAppear { urlInput = lastURL }
    }

    // 設定を反映してWebViewを再構築
    private func applySettings() {
        refreshID = UUID()
    }
    
    // URLを整形して読み込む
    private func loadNewURL() {
        var formatted = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.lowercased().hasPrefix("http") {
            formatted = "https://\(formatted)"
        }
        lastURL = formatted
        urlInput = formatted
        applySettings()
    }
}

// MARK: - WebView内部実装 (UIViewRepresentable)
extension Notification.Name {
    static let goBack = Notification.Name("goBack")
    static let goForward = Notification.Name("goForward")
}

struct WebViewComponent: UIViewRepresentable {
    let url: URL
    let ua: String
    let proxyHost: String
    let proxyPort: Int
    
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // プロキシ設定適用 (iOS 17.0+ 互換性チェック付き)
        if #available(iOS 17.0, *), !proxyHost.isEmpty {
            let proxy = WKProxyConfiguration(httpProxy: proxyHost, port: proxyPort)
            config.websiteDataStore.proxyConfigurations = [proxy]
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // UA設定 (重要: loadの前にセット)
        webView.customUserAgent = ua
        
        // 監視設定（KVO）
        context.coordinator.setupObservers(for: webView)
        
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // KVOと通知の管理クラス
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewComponent
        var cancellables = Set<AnyCancellable>()

        init(_ parent: WebViewComponent) {
            self.parent = parent
        }

        func setupObservers(for webView: WKWebView) {
            // プロパティ監視
            webView.publisher(for: \.isLoading).receive(on: DispatchQueue.main).assign(to: \.parent.isLoading, on: self).store(in: &cancellables)
            webView.publisher(for: \.estimatedProgress).receive(on: DispatchQueue.main).assign(to: \.parent.progress, on: self).store(in: &cancellables)
            webView.publisher(for: \.canGoBack).receive(on: DispatchQueue.main).assign(to: \.parent.canGoBack, on: self).store(in: &cancellables)
            webView.publisher(for: \.canGoForward).receive(on: DispatchQueue.main).assign(to: \.parent.canGoForward, on: self).store(in: &cancellables)
            
            // 通知センター経由の操作
            NotificationCenter.default.publisher(for: .goBack).sink { _ in webView.goBack() }.store(in: &cancellables)
            NotificationCenter.default.publisher(for: .goForward).sink { _ in webView.goForward() }.store(in: &cancellables)
        }
    }
}
