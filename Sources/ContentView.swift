import SwiftUI
import WebKit

// MARK: - 1. セッション・人格管理
struct TabSession: Identifiable {
    let id: Int
    let title: String
    let userAgent: String
    let dataStore: WKWebsiteDataStore
    let webView: WKWebView
    var memo: String = ""
    
    init(id: Int, ua: String) {
        self.id = id
        self.title = "\(id)"
        self.userAgent = ua
        
        // タブごとに独立したCookie/ストレージを持たせる
        self.dataStore = WKWebsiteDataStore.nonPersistent() 
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = self.dataStore
        config.processPool = WKProcessPool() // プロセスも完全分離
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = ua
        
        // デフォルトでGoogleを開く
        if let url = URL(string: "https://www.google.com") {
            self.webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - 2. メインビュー
struct ContentView: View {
    @State private var activeIndex: Int = 0
    @State private var recentIndex: Int = 0
    @State private var showMemo: Bool = false
    @State private var inputURL: String = "https://www.google.com"

    // 5つの異なる人格（UA）を定義
    @State private var sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // --- 上部ナビゲーションバー ---
            headerArea
                .background(Color(.systemBackground))

            // --- メインコンテンツエリア ---
            ZStack {
                ForEach(sessions.indices, id: \.self) { index in
                    // サスペンドロジック: 今と一個前以外は描画しない
                    if index == activeIndex || index == recentIndex {
                        WebViewContainer(webView: sessions[index].webView)
                            .opacity(index == activeIndex ? 1 : 0) // 重ねて表示を切り替え
                            .disabled(index != activeIndex)        // 非アクティブタブの操作無効化
                    }
                }
                
                // メモ機能（オーバーレイ）
                if showMemo {
                    memoOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // --- 下部タブツールバー ---
            footerArea
                .background(Color(.systemGroupedBackground))
        }
        .edgesIgnoringSafeArea(.bottom) // 背景を画面下端まで広げる
    }

    // MARK: - UIコンポーネント
    
    private var headerArea: some View {
        HStack(spacing: 8) {
            Button(action: { sessions[activeIndex].webView.goBack() }) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold))
            }
            .frame(width: 40, height: 44)
            
            TextField("URL", text: $inputURL, onCommit: loadURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            Button(action: { sessions[activeIndex].webView.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .frame(width: 40, height: 44)
            
            Button(action: clearCookies) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .frame(width: 40, height: 44)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var footerArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(sessions.indices, id: \.self) { index in
                    Button(action: { switchTab(to: index) }) {
                        VStack(spacing: 4) {
                            Text("\(index + 1)")
                                .font(.system(size: 20, weight: .bold))
                            
                            // 状態インジケーター
                            Circle()
                                .fill(activeIndex == index ? Color.blue : (recentIndex == index ? Color.blue.opacity(0.3) : Color.clear))
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity, height: 65)
                        .background(activeIndex == index ? Color.blue.opacity(0.1) : Color.clear)
                    }
                }
                
                // メモ開閉ボタン
                Button(action: { showMemo.toggle() }) {
                    Image(systemName: "note.text")
                        .font(.system(size: 20))
                        .frame(width: 60, height: 65)
                        .foregroundColor(showMemo ? .orange : .primary)
                }
            }
            // ホームインジケーター用の余白
            Spacer().frame(height: safeAreaBottom)
        }
    }

    private var memoOverlay: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("タブ \(activeIndex + 1) のメモ")
                    .font(.caption).bold()
                Spacer()
                Button("閉じる") { showMemo = false }.font(.caption)
            }
            .padding(.bottom, 4)
            
            TextEditor(text: $sessions[activeIndex].memo)
                .cornerRadius(8)
        }
        .padding(12)
        .background(Color(.systemYellow).opacity(0.95))
        .cornerRadius(15)
        .shadow(radius: 10)
        .frame(width: 300, height: 200)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.bottom, 80)
    }

    // MARK: - ロジック
    
    private func switchTab(to index: Int) {
        if activeIndex != index {
            recentIndex = activeIndex
            activeIndex = index
            // URLバーを表示中のURLに更新
            inputURL = sessions[activeIndex].webView.url?.absoluteString ?? ""
        }
    }

    private func loadURL() {
        var urlStr = inputURL.trimmingCharacters(in: .whitespaces)
        if !urlStr.lowercased().hasPrefix("http") { urlStr = "https://" + urlStr }
        if let url = URL(string: urlStr) {
            sessions[activeIndex].webView.load(URLRequest(url: url))
        }
    }

    private func clearCookies() {
        let store = sessions[activeIndex].dataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { records in
            store.removeData(ofTypes: dataTypes, for: records) {
                sessions[activeIndex].webView.reload()
            }
        }
    }

    private var safeAreaBottom: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }
}

// MARK: - 3. WebViewラッパー
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
