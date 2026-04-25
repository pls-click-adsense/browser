import SwiftUI
import WebKit

struct ContentView: View {
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "ifconfig.me"
    @State private var tab2Url: URL?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("BBS Stable Browser").font(.headline)
                HStack {
                    TextField("IP", text: $proxyHost).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $proxyPort).textFieldStyle(.roundedBorder).frame(width: 70)
                }
                HStack {
                    TextField("URL", text: $targetUrl).textFieldStyle(.roundedBorder)
                    Button("Go") {
                        let clean = targetUrl.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                        // 名前を「myproxy」に完全変更
                        tab2Url = URL(string: "myproxy://\(clean)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding().background(Color(.secondarySystemBackground))

            if let url = tab2Url {
                WebViewContainer(url: url, host: proxyHost, port: Int(proxyPort) ?? 8080)
            } else {
                Spacer()
            }
        }
    }
}

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
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        // myproxy:// -> https:// に戻してリクエスト
        let rawString = url.absoluteString.replacingOccurrences(of: "myproxy://", with: "https://")
        guard let rawUrl = URL(string: rawString) else { return }

        var request = URLRequest(url: rawUrl)
        request.httpMethod = urlSchemeTask.request.httpMethod
        request.allHTTPHeaderFields = urlSchemeTask.request.allHTTPHeaderFields

        // 実機でのクラッシュ防止：タスクを弱参照で保持するか、完了管理を徹底する
        session.dataTask(with: request) { data, response, error in
            // WebViewがすでにタスクを終了（stop）させていないかチェック
            // 簡易的にメインスレッドで一気に流す
            DispatchQueue.main.async {
                if let error = error {
                    urlSchemeTask.didFailWithError(error)
                } else {
                    if let res = response { urlSchemeTask.didReceive(res) }
                    if let d = data { urlSchemeTask.didReceive(d) }
                    urlSchemeTask.didFinish()
                }
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let host: String
    let port: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // ここで直接インスタンス化して登録
        config.setURLSchemeHandler(ProxySchemeHandler(host: host, port: port), forURLScheme: "myproxy")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}
