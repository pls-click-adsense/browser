import SwiftUI
import WebKit
import Network

struct ContentView: View {
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "https://ifconfig.me"
    @State private var loadWebView = false

    var body: some View {
        VStack {
            VStack(spacing: 10) {
                Text("BBS Stable Browser").font(.headline)
                TextField("Proxy IP", text: $proxyHost).textFieldStyle(.roundedBorder)
                TextField("Port", text: $proxyPort).textFieldStyle(.roundedBorder)
                TextField("Target URL", text: $targetUrl).textFieldStyle(.roundedBorder)
                Button("Launch Browser") {
                    loadWebView = false
                    // 0.2秒待ってから再ロード（クラッシュ防止の魔法）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        loadWebView = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            if loadWebView {
                WebViewContainer(urlString: targetUrl, host: proxyHost, port: Int(proxyPort) ?? 8080)
                    .id(proxyHost + proxyPort) // 設定が変わるたびに作り直す
            } else {
                Spacer()
            }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let urlString: String
    let host: String
    let port: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // --- iOS正規のプロキシ設定手順 ---
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        let proxyConfig = ProxyConfiguration(httpProxy: endpoint, httpsProxy: endpoint)
        
        // データストアに適用（これならクラッシュしない！）
        let store = WKWebsiteDataStore.nonPersistent()
        store.proxyConfigurations = [proxyConfig]
        config.websiteDataStore = store
        
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = URL(string: urlString) {
            uiView.load(URLRequest(url: url))
        }
    }
}
