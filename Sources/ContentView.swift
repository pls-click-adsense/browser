import SwiftUI
import WebKit

struct ContentView: View {
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "google.com"
    @State private var tab2Url: URL?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Custom Scheme Proxy").font(.headline)
                HStack {
                    TextField("Proxy Host", text: $proxyHost).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $proxyPort).textFieldStyle(.roundedBorder).frame(width: 70)
                }
                HStack {
                    TextField("Target (e.g. google.com)", text: $targetUrl).textFieldStyle(.roundedBorder)
                    Button("Go") {
                        // httpsを独自スキームに置換してロード
                        tab2Url = URL(string: "proxy-https://\(targetUrl)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))

            VStack(spacing: 0) {
                Text("🌐 Tab 1: Direct").font(.caption2).bold()
                WebViewContainer(url: URL(string: "https://www.google.com")!, proxyConfig: nil)
                
                Divider().frame(height: 5).background(Color.black)
                
                Text("🛡️ Tab 2: Proxy Scheme").font(.caption2).bold().foregroundColor(.blue)
                if let url = tab2Url {
                    WebViewContainer(url: url, proxyConfig: (host: proxyHost, port: Int(proxyPort) ?? 8080))
                } else {
                    Spacer()
                }
            }
        }
    }
}

// --- プロキシ通信を肩代わりするハンドラ ---
class ProxySchemeHandler: NSObject, WKURLSchemeHandler {
    let session: URLSession

    init(host: String, port: Int) {
        let config = URLSessionConfiguration.ephemeral
        // iOSで利用可能なキーのみを使用
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable: 1,
            kCFNetworkProxiesHTTPProxy: host,
            kCFNetworkProxiesHTTPPort: port
        ]
        self.session = URLSession(configuration: config)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let originalUrlString = url.absoluteString.replacingOccurrences(of: "proxy-", with: "").url?.absoluteString,
              let originalUrl = URL(string: originalUrlString) else { return }
        
        var request = URLRequest(url: originalUrl)
        request.httpMethod = urlSchemeTask.request.httpMethod
        
        // 元のリクエストのヘッダーをコピー（重要：これがないとサイトが正しく表示されないことが多い）
        if let allHeaders = urlSchemeTask.request.allHTTPHeaderFields {
            request.allHTTPHeaderFields = allHeaders
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                urlSchemeTask.didFailWithError(error)
                return
            }
            if let response = response {
                urlSchemeTask.didReceive(response)
            }
            if let data = data {
                urlSchemeTask.didReceive(data)
            }
            urlSchemeTask.didFinish()
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

// --- WebViewラッパー ---
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let proxyConfig: (host: String, port: Int)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // プロキシ設定がある場合のみ、ハンドラを登録
        if let proxy = proxyConfig {
            config.setURLSchemeHandler(ProxySchemeHandler(host: proxy.host, port: proxy.port), forURLScheme: "proxy-https")
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}

extension String {
    var url: URL? { URL(string: self) }
}
