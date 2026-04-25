import SwiftUI
import WebKit

// MARK: - タブの情報を管理する構造体
struct TabSession: Identifiable {
    let id: Int
    let title: String
    let userAgent: String
    let dataStore: WKWebsiteDataStore
    var urlString: String = "https://www.google.com"
    var memo: String = ""
    
    // 各タブ専用のWebViewインスタンスを保持
    let webView: WKWebView
    
    init(id: Int, ua: String) {
        self.id = id
        self.title = "\(id)"
        self.userAgent = ua
        
        // 1. データストアの分離
        self.dataStore = WKWebsiteDataStore.nonPersistent() // 今回はメモリ型。永続化なら identifier 指定
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = self.dataStore
        config.processPool = WKProcessPool() // プロセスも分離
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = ua
    }
}

struct ContentView: View {
    @State private var sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]
    
    @State private var activeIndex: Int = 0
    @State private var recentIndex: Int = 0
    @State private var showMemo: Bool = false
    @State private var inputURL: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // --- Header: URLバー & 操作系 ---
            HStack {
                Button(action: { sessions[activeIndex].webView.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                TextField("URL", text: $inputURL, onCommit: loadURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                
                Button(action: { sessions[activeIndex].webView.reload() }) {
                    Image(systemName: "arrow.clockwise")
                }
                Button(action: clearCookies) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            .padding()

            // --- Body: WebView & メモ ---
            ZStack {
                ForEach(sessions.indices, id: \.self) { index in
                    // 仕様: ActiveとRecentのみ保持、それ以外は描画しない（サスペンド）
                    if index == activeIndex || index == recentIndex {
                        WebViewContainer(webView: sessions[index].webView)
                            .opacity(index == activeIndex ? 1 : 0) // 見えるのはActiveのみ
                            .onAppear {
                                if sessions[index].webView.url == nil {
                                    loadURL()
                                }
                            }
                    }
                }
                
                if showMemo {
                    TextEditor(text: $sessions[activeIndex].memo)
                        .padding()
                        .background(Color.yellow.opacity(0.9))
                        .frame(width: 250)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                        .padding(.trailing, 20)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // --- Footer: ツールバー ---
            HStack(spacing: 0) {
                ForEach(sessions.indices, id: \.self) { index in
                    Button(action: { switchTab(to: index) }) {
                        Text(sessions[index].title)
                            .frame(maxWidth: .infinity, maxHeight: 50)
                            .background(activeIndex == index ? Color.blue : (recentIndex == index ? Color.blue.opacity(0.3) : Color.clear))
                            .foregroundColor(activeIndex == index ? .white : .primary)
                            .border(Color.gray.opacity(0.2))
                    }
                }
                
                Button(action: { showMemo.toggle() }) {
                    Image(systemName: "note.text")
                        .frame(width: 50, height: 50)
                        .background(showMemo ? Color.orange : Color.clear)
                        .foregroundColor(.primary)
                }
            }
        }
    }

    // MARK: - ロジック
    private func switchTab(to index: Int) {
        if activeIndex != index {
            recentIndex = activeIndex
            activeIndex = index
            inputURL = sessions[activeIndex].webView.url?.absoluteString ?? ""
        }
    }

    private func loadURL() {
        var urlStr = inputURL
        if !urlStr.hasPrefix("http") { urlStr = "https://" + urlStr }
        if let url = URL(string: urlStr) {
            sessions[activeIndex].webView.load(URLRequest(url: url))
        }
    }

    private func clearCookies() {
        let store = sessions[activeIndex].dataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                sessions[activeIndex].webView.reload()
            }
        }
    }
}

// WKWebViewをSwiftUIで使うためのラッパー
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
