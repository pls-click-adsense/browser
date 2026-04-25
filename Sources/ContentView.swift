import SwiftUI
import WebKit
import Combine
import Foundation

// MARK: - Browser View
struct ContentView: View {
    // --- 1. UserDefaults Persistence ---
    @AppStorage("selectedUA") private var selectedUA: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"
    @AppStorage("proxyHost") private var proxyHost: String = ""
    @AppStorage("proxyPort") private var proxyPort: Int = 8080
    @AppStorage("lastURL") private var lastURL: String = "https://www.google.com"
    
    // --- 2. Internal States ---
    @State private var urlInput: String = ""
    @State private var isLoading: Bool = false
    @State private var estimatedProgress: Double = 0.0
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var refreshID = UUID() 
    
    // --- 3. User Agent Dictionary (iOS 18.4.1 Compliant) ---
    let uaOptions: [String: String] = [
        "Safari": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1",
        "Chrome": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/134.0.6998.92 Mobile/15E148 Safari/604.1",
        "Firefox": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/136.0 Mobile/15E148 Safari/604.1",
        "Edge": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 EdgiOS/134.0.3124.96 Mobile/15E148 Safari/604.1",
        "Opera": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) OPiOS/10.0.0 Mobile/15E148 Safari/604.1"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header Settings Panel
            VStack(spacing: 12) {
                Picker("User Agent", selection: $selectedUA) {
                    ForEach(uaOptions.keys.sorted(), id: \.self) { key in
                        Text(key).tag(uaOptions[key]!)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedUA) { _, _ in applySettings() }
                
                HStack {
                    Image(systemName: "network")
                    TextField("Proxy Host", text: $proxyHost)
                    TextField("Port", value: $proxyPort, formatter: NumberFormatter())
                        .frame(width: 70)
                    Button("Apply") { applySettings() }
                        .buttonStyle(.borderedProminent)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    TextField("Enter URL", text: $urlInput, onCommit: { loadNewURL() })
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
            
            // Progress Bar
            if isLoading {
                ProgressView(value: estimatedProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 3)
            }

            // WebView
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
            .id(refreshID)
            
            // Bottom Toolbar
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

    private func applySettings() { refreshID = UUID() }
    
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

// MARK: - WebView Implementation
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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // --- PROXY FIX: iOS 17+ GUARD ---
        #if canImport(WebKit)
        if #available(iOS 17.0, *) {
            if !proxyHost.isEmpty {
                // Explicitly use the full namespace to avoid scope issues
                let proxyConfig = WebKit.WKProxyConfiguration(httpProxy: proxyHost, port: proxyPort)
                config.websiteDataStore.proxyConfigurations = [proxyConfig]
            }
        }
        #endif

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = ua
        context.coordinator.setupObservers(for: webView)
        
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewComponent
        var cancellables = Set<AnyCancellable>()

        init(_ parent: WebViewComponent) { self.parent = parent }

        func setupObservers(for webView: WKWebView) {
            webView.publisher(for: \.isLoading).receive(on: DispatchQueue.main).assign(to: \.parent.isLoading, on: self).store(in: &cancellables)
            webView.publisher(for: \.estimatedProgress).receive(on: DispatchQueue.main).assign(to: \.parent.progress, on: self).store(in: &cancellables)
            webView.publisher(for: \.canGoBack).receive(on: DispatchQueue.main).assign(to: \.parent.canGoBack, on: self).store(in: &cancellables)
            webView.publisher(for: \.canGoForward).receive(on: DispatchQueue.main).assign(to: \.parent.canGoForward, on: self).store(in: &cancellables)
            
            NotificationCenter.default.publisher(for: .goBack).sink { _ in webView.goBack() }.store(in: &cancellables)
            NotificationCenter.default.publisher(for: .goForward).sink { _ in webView.goForward() }.store(in: &cancellables)
        }
    }
}
