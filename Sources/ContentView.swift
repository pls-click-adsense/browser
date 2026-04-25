import SwiftUI
import WebKit
import Swifter

// --- メイン画面 ---
struct ContentView: View {
    @StateObject private var proxyController = SingleProxyController()
    
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "http://example.com"
    @State private var tab2Url: URL = URL(string: "about:blank")!

    var body: some View {
        VStack(spacing: 0) {
            // 設定エリア
            VStack(spacing: 8) {
                Text("Proxy Control Panel").font(.headline)
                HStack {
                    TextField("Proxy Host", text: $proxyHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $proxyPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                HStack {
                    TextField("Target URL", text: $targetUrl)
                        .textFieldStyle(.roundedBorder)
                    Button("Go") {
                        proxyController.updateConfig(host: proxyHost, port: Int(proxyPort) ?? 8080)
                        tab2Url = URL(string: "http://localhost:8081/fetch?url=\(targetUrl)")!
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))

            // 2タブ同時表示
            VStack(spacing: 0) {
                // タブ1: 直通
                VStack(alignment: .leading, spacing: 2) {
                    Text(" 🌐 Tab 1: Direct (No Proxy)").font(.caption2).bold()
                    WebViewContainer(url: URL(string: "https://www.google.com")!)
                }
                .border(Color.gray, width: 1)

                Divider().frame(height: 5).background(Color.black)

                // タブ2: プロキシ経由
                VStack(alignment: .leading, spacing: 2) {
                    Text(" 🛡️ Tab 2: Proxy Route").font(.caption2).bold().foregroundColor(.blue)
                    WebViewContainer(url: tab2Url)
                }
                .border(Color.blue, width: 2)
            }
        }
        .onAppear {
            proxyController.startServer()
        }
    }
}

// --- プロキシ中継サーバー ---
class SingleProxyController: ObservableObject {
    private let server = HttpServer()
    private var currentHost: String = ""
    private var currentPort: Int = 8080
    
    func updateConfig(host: String, port: Int) {
        self.currentHost = host
        self.currentPort = port
    }
    
    func startServer() {
        server["/fetch"] = { [weak self] request in
            guard let self = self,
                  let urlString = request.queryParams.first(where: { $0.0 == "url" })?.1,
                  let targetUrl = URL(string: urlString) else {
                return .badRequest(nil)
            }
            
            let config = URLSessionConfiguration.ephemeral
            if !self.currentHost.isEmpty {
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable: 1,
                    kCFNetworkProxiesHTTPProxy: self.currentHost,
                    kCFNetworkProxiesHTTPPort: self.currentPort
                ]
            }
            
            let session = URLSession(configuration: config)
            var responseData: Data?
            let semaphore = DispatchSemaphore(value: 0)
            
            session.dataTask(with: targetUrl) { data, _, _ in
                responseData = data
                semaphore.signal()
            }.resume()
            
            _ = semaphore.wait(timeout: .now() + 15)
            
            if let data = responseData {
                return .ok(.data(data))
            }
            return .internalServerError
        }
        try? server.start(8081)
    }
}

// --- WebViewラッパー ---
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}
