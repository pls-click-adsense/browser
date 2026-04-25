import SwiftUI
import WebKit
import Combine
import Foundation

// MARK: - ブラウザの全機能を管理するContentView
struct ContentView: View {
    // --- UserDefaultsによる永続化 ---
    @AppStorage("selectedUA") private var selectedUA: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"
    @AppStorage("proxyHost") private var proxyHost: String = ""
    @AppStorage("proxyPort") private var proxyPort: Int = 8080
    @AppStorage("lastURL") private var lastURL: String = "https://www.google.com"
    
    // --- 状態管理 ---
    @State private var urlInput: String = ""
    @State private var isLoading: Bool = false
    @State private var estimatedProgress: Double = 0.0
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var refreshID = UUID() // 設定変更時にWebViewを物理的に作り直す
    
    // --- UAリスト (iOS 18.4.1 完全準拠) ---
    let uaOptions: [String: String] = [
        "Safari": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1",
        "Chrome": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/134.0.6998.92 Mobile/15E148 Safari/604.1",
        "Firefox": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/136.0 Mobile/15E148 Safari/604.1",
        "Edge": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 EdgiOS/134.0.3124.96 Mobile/15E148 Safari/604.1",
        "Opera": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OPiOS/10.0.0 Mobile/15E148 Safari/604.1"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // --- 設定・コントロールパネル ---
            VStack(spacing: 10) {
                // UAセレクター
                Picker("User Agent", selection: $selectedUA) {
                    ForEach(uaOptions.keys.sorted(), id: \.self) { key in
                        Text(key).tag(uaOptions[key]!)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedUA) { _ in applySettings() }
                
                // プロキシ設定
                HStack {
                    Label("", systemImage: "network").labelStyle(.iconOnly)
                    TextField("Proxy Host", text: $proxyHost)
                    TextField("Port", value: $proxyPort, formatter: NumberFormatter())
                        .frame(width: 60)
                    Button("適用") { applySettings() }
                        .buttonStyle(.borderedProminent)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                // アドレスバー
                HStack {
                    TextField("URLを入力", text: $urlInput, onCommit: { loadNewURL() })
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(8)
                        .background(Color(.systemBackground))
                        .cornerRadius(8)
                    
                    Button(action: loadNewURL) {
                        Image(systemName: "magnifyingglass.circle.fill").font(.title2)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            
            // 読み込み進捗バー
            if isLoading {
                ProgressView(value: estimatedProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 2)
            }

            // --- WebViewコンポーネント ---
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
            .id(refreshID) // 設定変更時にWebViewを再生成
            
            // --- 下部ツールバー ---
            HStack {
                Button(action: { NotificationCenter.default.post(name: .goBack, object: nil) }) {
                    Image(systemName: "chevron.left")
                }.disabled(!canGoBack)
                Spacer()
                Button(action: { refreshID = UUID() }) {
                    Image(systemName: "arrow.clockwise")
                }
                Spacer()
                Button(action: { NotificationCenter.default.post(name: .goForward, object: nil) }) {
                    Image(systemName: "chevron.right")
                }.disabled(!canGoForward)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
        }
        .onAppear { urlInput = lastURL }
    }

    private func applySettings() { refreshID = UUID() }
    
    private func loadNewURL() {
        let formatted = urlInput.lowercased().hasPrefix("http") ? urlInput : "https://\(urlInput)"
        lastURL = formatted
        urlInput = formatted
        applySettings()
    }
}

// MARK: - WKWebViewの実装と通知定義
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
        
        // プロキシ注入
        if !proxyHost.isEmpty {
            let proxy = WKProxyConfiguration(httpProxy: proxyHost, port: proxyPort)
            config.websiteDataStore.proxyConfigurations = [proxy]
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ua // ロード前にセット
        
        // 戻る・進むの通知監視
        context.coordinator.setupObservers(for: webView)
        
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewComponent
        var cancellables = Set<AnyCancellable>()

        init(_ parent: WebViewComponent) {
            self.parent = parent
        }

        func setupObservers(for webView: WKWebView) {
            webView.publisher(for: \.isLoading).assign(to: \.parent.isLoading, on: self).store(in: &cancellables)
            webView.publisher(for: \.estimatedProgress).assign(to: \.parent.progress, on: self).store(in: &cancellables)
            webView.publisher(for: \.canGoBack).assign(to: \.parent.canGoBack, on: self).store(in: &cancellables)
            webView.publisher(for: \.canGoForward).assign(to: \.parent.canGoForward, on: self).store(in: &cancellables)
            
            NotificationCenter.default.publisher(for: .goBack).sink { _ in webView.goBack() }.store(in: &cancellables)
            NotificationCenter.default.publisher(for: .goForward).sink { _ in webView.goForward() }.store(in: &cancellables)
        }
    }
}
