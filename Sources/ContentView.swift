import SwiftUI
import WebKit

struct ContentView: View {
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "https://ifconfig.me"
    @State private var loadWebView = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("BBS Final Controller").font(.headline)
                HStack {
                    TextField("IP", text: $proxyHost).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $proxyPort).textFieldStyle(.roundedBorder).frame(width: 70)
                }
                HStack {
                    TextField("URL", text: $targetUrl).textFieldStyle(.roundedBorder)
                    Button("Go") {
                        loadWebView = false
                        // 少し遅延させて再描画を強制する
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            loadWebView = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding().background(Color(.secondarySystemBackground))

            if loadWebView {
                // 独自のスキームを使わず、普通のURLを渡す
                WebViewContainer(urlString: targetUrl, host: proxyHost, port: Int(proxyPort) ?? 8080)
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
        let store = WKWebsiteDataStore.nonPersistent() // キャッシュを残さないエフェメラル設定
        
        // iOS 17+ のプロキシ設定を反映させる試み
        let proxyConfig = [
            "HTTPEnable": 1,
            "HTTPProxy": host,
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port,
            "ProxyAutoConfigEnable": 0
        ] as [String : Any]
        
        // 内部プロパティへの安全なアクセス
        store.setValue([proxyConfig], forKey: "_proxyConfigurations")
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
