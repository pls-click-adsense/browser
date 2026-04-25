import SwiftUI
import WebKit

struct TabSession: Identifiable {
    let id: Int
    let userAgent: String
    let webView: WKWebView
    var memo: String = ""
    
    init(id: Int, ua: String) {
        self.id = id
        self.userAgent = ua
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = ua
        if let url = URL(string: "https://duckduckgo.com") {
            self.webView.load(URLRequest(url: url))
        }
    }
}

struct ContentView: View {
    @State private var activeIndex: Int = 0
    @State private var recentIndex: Int = 0
    @State private var showMemo: Bool = false
    @State private var inputURL: String = "https://duckduckgo.com"
    @State private var sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header (URLバー)
            HStack(spacing: 8) {
                Button(action: { sessions[activeIndex].webView.goBack() }) {
                    Image(systemName: "chevron.left")
                }.frame(width: 44, height: 44)
                
                TextField("Search or URL", text: $inputURL, onCommit: loadURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                
                Button(action: { sessions[activeIndex].webView.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }.frame(width: 44, height: 44)
            }
            .padding(.horizontal)
            .background(Color(.systemBackground))

            // Main (ブラウザ表示)
            ZStack {
                ForEach(0..<5) { i in
                    if i == activeIndex || i == recentIndex {
                        WebViewContainer(webView: sessions[i].webView)
                            .opacity(i == activeIndex ? 1 : 0)
                    }
                }
                
                if showMemo {
                    TextEditor(text: $sessions[activeIndex].memo)
                        .frame(width: 250, height: 200)
                        .background(Color.yellow.opacity(0.9))
                        .cornerRadius(10)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // ここで全画面を確保
        }
        // Footer (タブ切り替え) を safeAreaInset で配置
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                ForEach(0..<5) { i in
                    Button(action: { 
                        recentIndex = activeIndex
                        activeIndex = i 
                        inputURL = sessions[i].webView.url?.absoluteString ?? ""
                    }) {
                        Text("\(i + 1)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(activeIndex == i ? Color.blue.opacity(0.2) : Color.clear)
                    }
                }
                
                Button(action: { showMemo.toggle() }) {
                    Image(systemName: "note.text")
                        .frame(width: 60, height: 60)
                        .foregroundColor(showMemo ? .orange : .primary)
                }
            }
            .background(Material.thinMaterial) // 背景を透過素材に
        }
    }

    private func loadURL() {
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if trimmed.contains(".") && !trimmed.contains(" ") {
            path = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path = "https://duckduckgo.com/?q=\(query)"
        }
        
        if let url = URL(string: path) {
            sessions[activeIndex].webView.load(URLRequest(url: url))
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
