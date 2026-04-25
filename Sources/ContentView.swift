import SwiftUI
import WebKit
import Combine

// MARK: - CookieStore

class CookieStore {
    static func save(tabId: Int, cookies: [HTTPCookie]) {
        let data = cookies.compactMap { cookie -> [String: Any]? in
            var dict: [String: Any] = [:]
            for (key, value) in cookie.properties ?? [:] {
                dict[key.rawValue] = value
            }
            return dict
        }
        UserDefaults.standard.set(data, forKey: "cookies_tab_\(tabId)")
    }

    static func load(tabId: Int) -> [HTTPCookie] {
        guard let data = UserDefaults.standard.array(forKey: "cookies_tab_\(tabId)") as? [[String: Any]] else {
            return []
        }
        return data.compactMap { dict in
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: dict.map {
                (HTTPCookiePropertyKey($0.key), $0.value)
            }))
        }
    }

    static func clear(tabId: Int) {
        UserDefaults.standard.removeObject(forKey: "cookies_tab_\(tabId)")
    }
}

// MARK: - TabSession

class TabSession: Identifiable, ObservableObject {
    let id: Int
    let userAgent: String
    let webView: WKWebView

    @Published var currentURL: String = "https://duckduckgo.com"
    @Published var memo: String = ""

    private var cancellables = Set<AnyCancellable>()

    init(id: Int, ua: String) {
        self.id = id
        self.userAgent = ua

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = ua

        let cookies = CookieStore.load(tabId: id)
        let cookieStore = config.websiteDataStore.httpCookieStore
        for cookie in cookies {
            cookieStore.setCookie(cookie) {}
        }

        // KVO: URLの変化を監視してcurrentURLに反映
        webView.publisher(for: \.url)
            .compactMap { $0?.absoluteString }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.currentURL = url
            }
            .store(in: &cancellables)
    }

    func saveCookies(completion: (() -> Void)? = nil) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            CookieStore.save(tabId: self.id, cookies: cookies)
            completion?()
        }
    }

    func clearCookies(completion: (() -> Void)? = nil) {
        CookieStore.clear(tabId: id)
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                completion?()
            }
        }
    }

    func loadInitialURL() {
        if let url = URL(string: "https://duckduckgo.com") {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var activeIndex: Int = 0
    @State private var showMemo: Bool = false
    @State private var inputURL: String = "https://duckduckgo.com"
    @State private var isEditingURL: Bool = false
    @State private var showClearAlert: Bool = false

    let sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        VStack(spacing: 0) {

            // MARK: ヘッダー
            headerView

            // MARK: WebView + メモオーバーレイ
            ZStack(alignment: .bottomTrailing) {
                ForEach(0..<5) { i in
                    WebViewContainer(webView: sessions[i].webView)
                        .opacity(i == activeIndex ? 1 : 0)
                }

                if showMemo {
                    memoOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: フッター
            footerView
        }
        // キーボードのみ SafeArea を無視（レイアウトを崩さない）
        .ignoresSafeArea(.keyboard)
        .onAppear {
            sessions[0].loadInitialURL()
        }
        // アクティブタブのURLをリアルタイムでURLバーに反映
        .onReceive(sessions[activeIndex].$currentURL) { url in
            if !isEditingURL {
                inputURL = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            for session in sessions {
                session.saveCookies()
            }
        }
    }

    // MARK: - ヘッダービュー

    private var headerView: some View {
        HStack(spacing: 4) {
            Button(action: { sessions[activeIndex].webView.goBack() }) {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 44)
            }

            Button(action: { sessions[activeIndex].webView.goForward() }) {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 44)
            }

            // URLバー：編集中は入力値、非編集中はWebViewの現在URL
            TextField("Search or URL", text: $inputURL, onEditingChanged: { editing in
                isEditingURL = editing
                if editing {
                    // 編集開始時に全選択しやすいよう現在URLをセット済み
                }
            }, onCommit: {
                isEditingURL = false
                loadURL()
            })
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .keyboardType(.URL)
            .autocapitalization(.none)
            .disableAutocorrection(true)

            Button(action: { sessions[activeIndex].webView.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 36, height: 44)
            }

            Button(action: { showClearAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .frame(width: 36, height: 44)
            }
            .alert("クッキーを削除", isPresented: $showClearAlert) {
                Button("削除", role: .destructive) {
                    sessions[activeIndex].clearCookies {
                        DispatchQueue.main.async {
                            sessions[activeIndex].loadInitialURL()
                            inputURL = "https://duckduckgo.com"
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("タブ\(activeIndex + 1)のクッキーと履歴を削除します")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 60)
        .background(Color(.systemBackground))
    }

    // MARK: - メモオーバーレイ

    private var memoOverlay: some View {
        TextEditor(text: sessions[activeIndex].memoBinding)
            .frame(width: 250, height: 200)
            .background(Color.yellow.opacity(0.9))
            .cornerRadius(10)
            .padding()
    }

    // MARK: - フッタービュー

    private var footerView: some View {
        HStack(spacing: 0) {
            ForEach(0..<5) { i in
                Button(action: { switchTab(to: i) }) {
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
        .background(Material.thinMaterial)
    }

    // MARK: - タブ切り替え

    private func switchTab(to index: Int) {
        sessions[activeIndex].saveCookies()
        activeIndex = index

        // 切り替え先のURLをURLバーに反映
        inputURL = sessions[index].currentURL

        // 未ロードなら初期ページを開く
        if sessions[index].webView.url == nil {
            sessions[index].loadInitialURL()
        }
    }

    // MARK: - URL読み込み

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

// MARK: - TabSession メモバインディング拡張

extension TabSession {
    var memoBinding: Binding<String> {
        Binding(
            get: { self.memo },
            set: { self.memo = $0 }
        )
    }
}

// MARK: - WebViewContainer

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
