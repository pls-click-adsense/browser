import Foundation
import UIKit
import SwiftUI
import WebKit
import Network

// MARK: - Tabモデル
class Tab: Identifiable, ObservableObject {
    let id = UUID()
    let webView: WKWebView

    init(ua: String, proxyHost: String?, proxyPort: String?) {
        let config = WKWebViewConfiguration()

        // タブごとに分離（重要）
        config.processPool = WKProcessPool()

        // 永続ストア
        let store = WKWebsiteDataStore.default()

        // Proxy（iOS17+）
        if let host = proxyHost,
           let portStr = proxyPort,
           let portInt = Int(portStr),
           let port = NWEndpoint.Port(rawValue: UInt16(portInt)) {

            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
            let proxy = ProxyConfiguration(httpCONNECTProxy: endpoint)
            store.proxyConfigurations = [proxy]
        }

        config.websiteDataStore = store

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = ua

        self.webView = wv
    }
}

// MARK: - タブ管理
class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedIndex: Int = 0

    let userAgents: [String] = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)...",
        "Mozilla/5.0 (Linux; Android 13; Pixel 7)...",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64)...",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0)...",
        "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)..."
    ]

    @Published var proxyHost: String = ""
    @Published var proxyPort: String = ""

    init() {
        loadProxy()
        addTab()
    }

    func addTab() {
        let tab = Tab(
            ua: userAgents[0],
            proxyHost: proxyHost.isEmpty ? nil : proxyHost,
            proxyPort: proxyPort.isEmpty ? nil : proxyPort
        )
        tabs.append(tab)
        selectedIndex = tabs.count - 1
    }

    func closeTab(index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        selectedIndex = max(0, selectedIndex - 1)
    }

    func currentTab() -> Tab? {
        guard tabs.indices.contains(selectedIndex) else { return nil }
        return tabs[selectedIndex]
    }

    func load(url: String) {
        guard let u = URL(string: url),
              let tab = currentTab() else { return }
        tab.webView.load(URLRequest(url: u))
    }

    // Proxy保存
    func saveProxy() {
        UserDefaults.standard.set(proxyHost, forKey: "proxyHost")
        UserDefaults.standard.set(proxyPort, forKey: "proxyPort")
    }

    func loadProxy() {
        proxyHost = UserDefaults.standard.string(forKey: "proxyHost") ?? ""
        proxyPort = UserDefaults.standard.string(forKey: "proxyPort") ?? ""
    }

    // Cookie削除（全体）
    func clearAllCookies() {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()

        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records, completionHandler: {})
        }
    }
}

// MARK: - WebView Wrapper
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - UI
struct ContentView: View {
    @StateObject var manager = TabManager()
    @State private var urlString = "https://example.com"

    var body: some View {
        VStack {

            // URLバー
            HStack {
                TextField("URL", text: $urlString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Go") {
                    manager.load(url: urlString)
                }

                Button("+Tab") {
                    manager.addTab()
                }
            }

            // タブ一覧
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(manager.tabs.enumerated()), id: \\.1.id) { i, tab in
                        Button("Tab \(i)") {
                            manager.selectedIndex = i
                        }
                    }
                }
            }

            // Proxy設定
            HStack {
                TextField("Proxy Host", text: $manager.proxyHost)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                TextField("Port", text: $manager.proxyPort)
                    .frame(width: 80)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Save Proxy") {
                    manager.saveProxy()
                }
            }

            // Cookie削除
            Button("Clear Cookies") {
                manager.clearAllCookies()
            }

            // WebView
            if let tab = manager.currentTab() {
                WebView(webView: tab.webView)
            }
        }
        .padding()
    }
}
