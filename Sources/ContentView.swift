import SwiftUI
import WebKit

struct ContentView: View {
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "ifconfig.me" // 最初はシンプルなサイトがおすすめ
    @State private var tab2Url: URL?

    var body: some View {
        VStack(spacing: 0) {
            // プロキシ入力パネル
            VStack(spacing: 8) {
                Text("Double Agent Browser").font(.headline)
                HStack {
                    TextField("Proxy Host", text: $proxyHost).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $proxyPort).textFieldStyle(.roundedBorder).frame(width: 70)
                }
                HStack {
                    TextField("Target (e.g. google.com)", text: $targetUrl).textFieldStyle(.roundedBorder)
                    Button("Go") {
                        // 独自スキームに変換してロード
                        let cleanUrl = targetUrl.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                        tab2Url = URL(string: "proxy-https://\(cleanUrl)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))

            // 2画面分割表示
            VStack(spacing: 0) {
                Text("🌐 Tab 1: Direct (Normal)").font(.caption2).bold()
                WebViewContainer(url: URL(string: "https://ifconfig.me")!, proxyConfig: nil)
                
                Divider().frame(height: 5).background(Color.black)
                
                Text("🛡️ Tab 2: Proxy Guided").font(.caption2).bold().foregroundColor(.blue)
                if let url = tab2Url {
                    WebViewContainer(url: url, proxyConfig: (host: proxyHost, port: Int(proxyPort) ?? 8080))
                } else {
                    Spacer().frame(maxWidth: .infinity).background(Color(.systemGray6))
                }
            }
        }
    }
}

// --- 通信を乗っ取るハンドラ ---
class ProxySchemeHandler: NSObject, WKURLSchemeHandler {
    let session: URLSession

    init(host: String, port: Int) {
        let config = URLSessionConfiguration.ephemeral
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

// --- WebViewとDelegateのセットアップ ---
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let proxyConfig: (host: String, port: Int)?

    func makeCoordinator() -> Coordinator {
        Coordinator(proxyConfig: proxyConfig)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let proxy = proxyConfig {
            config.setURLSchemeHandler(ProxySchemeHandler(host: proxy.host, port: proxy.port), forURLScheme: "proxy-https")
            config.setURLSchemeHandler(ProxySchemeHandler(host: proxy.host, port: proxy.port), forURLScheme: "proxy-http")
        }
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let proxyConfig: (host: String, port: Int)?

        init(proxyConfig: (host: String, port: Int)?) {
            self.proxyConfig = proxyConfig
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, proxyConfig != nil else {
                decisionHandler(.allow)
                return
            }

            // https/httpで通信しようとしたら、独自スキームにリダイレクトしてハンドラを強制起動
            if url.scheme == "https" || url.scheme == "http" {
                let newUrlString = "proxy-" + url.absoluteString
                if let newUrl = URL(string: newUrlString) {
                    webView.load(URLRequest(url: newUrl))
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

extension String {
    var url: URL? { URL(string: self) }
}
