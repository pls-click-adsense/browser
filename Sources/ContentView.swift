import SwiftUI
import WebKit

struct ContentView: View {
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""
    @State private var targetUrl: String = "https://ifconfig.me"
    @State private var tab2Url: URL?
    @State private var logs: [String] = ["--- Device Log Start ---"]

    var body: some View {
        VStack(spacing: 0) {
            // 入力エリア
            VStack(spacing: 8) {
                Text("BBS Proxy (On-Device Log)").font(.headline)
                HStack {
                    TextField("IP", text: $proxyHost).textFieldStyle(.roundedBorder)
                    TextField("Port", text: $proxyPort).textFieldStyle(.roundedBorder).frame(width: 70)
                }
                HStack {
                    TextField("URL", text: $targetUrl).textFieldStyle(.roundedBorder)
                    Button("Go") {
                        addLog("🌐 Loading: \(targetUrl)")
                        let clean = targetUrl.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
                        tab2Url = URL(string: "proxy-https://\(clean)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))

            // ブラウザエリア
            VStack(spacing: 0) {
                if let url = tab2Url {
                    WebViewContainer(url: url, proxyConfig: (host: proxyHost, port: Int(proxyPort) ?? 8080)) { log in
                        addLog(log)
                    }
                } else {
                    Spacer().frame(maxHeight: .infinity)
                }
            }
            .frame(height: 300) // ブラウザの高さを固定
            
            Divider().background(Color.red)

            // 実機用ログ表示エリア
            VStack(alignment: .leading) {
                Text("Console Logs:").font(.caption).bold().padding(.horizontal)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<logs.count, id: \.self) { i in
                                Text(logs[i])
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal)
                                    .id(i)
                            }
                        }
                    }
                    .onChange(of: logs.count) { _ in
                        proxy.scrollTo(logs.count - 1)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.green)
        }
    }

    func addLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        logs.append("[\(time)] \(message)")
    }
}

class ProxySchemeHandler: NSObject, WKURLSchemeHandler {
    let session: URLSession
    var onLog: (String) -> Void

    init(host: String, port: Int, onLog: @escaping (String) -> Void) {
        self.onLog = onLog
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
              let rawUrl = URL(string: url.absoluteString.replacingOccurrences(of: "proxy-", with: "")) else { return }
        
        DispatchQueue.main.async { self.onLog("🚀 Req: \(rawUrl.lastPathComponent)") }

        var request = URLRequest(url: rawUrl)
        request.httpMethod = urlSchemeTask.request.httpMethod
        request.allHTTPHeaderFields = urlSchemeTask.request.allHTTPHeaderFields

        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.onLog("❌ Err: \(error.localizedDescription)")
                    urlSchemeTask.didFailWithError(error)
                    return
                }
                if let res = response as? HTTPURLResponse {
                    self.onLog("✅ Res: \(res.statusCode) (\(rawUrl.lastPathComponent))")
                    urlSchemeTask.didReceive(res)
                }
                if let data = data { urlSchemeTask.didReceive(data) }
                urlSchemeTask.didFinish()
            }
        }
        task.resume()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let proxyConfig: (host: String, port: Int)?
    let onLog: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let proxy = proxyConfig {
            let handler = ProxySchemeHandler(host: proxy.host, port: proxy.port, onLog: onLog)
            config.setURLSchemeHandler(handler, forURLScheme: "proxy-https")
            config.setURLSchemeHandler(handler, forURLScheme: "proxy-http")
        }
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}
