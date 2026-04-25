import SwiftUI
import WebKit

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

// classにして参照型にする
class TabSession: Identifiable, ObservableObject {
    let id: Int
    let userAgent: String
    let webView: WKWebView
    var memo: String = ""
    
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

struct ContentView: View {
    @State private var activeIndex: Int = 0
    @State private var recentIndex: Int = 0
    @State private var showMemo: Bool = false
    @State private var inputURL: String = "https://duckduckgo.com"
    @State private var showClearAlert: Bool = false
    @State private var memos: [String] = Array(repeating: "", count: 5)
    
    let sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]
    
    private let headerHeight: CGFloat = 60
    private let footerHeight: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let webHeight = geo.size.height - headerHeight - footerHeight

            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button(action: { sessions[activeIndex].webView.goBack() }) {
                        Image(systemName: "chevron.left")
                    }.frame(width: 36, height: headerHeight)
                    
                    Button(action: { sessions[activeIndex].webView.goForward() }) {
                        Image(systemName: "chevron.right")
                    }.frame(width: 36, height: headerHeight)
                    
                    TextField("Search or URL", text: $inputURL, onCommit: loadURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    
                    Button(action: { sessions[activeIndex].webView.reload() }) {
                        Image(systemName: "arrow.clockwise")
                    }.frame(width: 36, height: headerHeight)
                    
                    Button(action: { showClearAlert = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .frame(width: 36, height: headerHeight)
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
                .frame(height: headerHeight)
                .background(Color(.systemBackground))

                ZStack {
                    ForEach(0..<5) { i in
                        WebViewContainer(webView: sessions[i].webView)
                            .opacity(i == activeIndex ? 1 : 0)
                    }
                    
                    if showMemo {
                        TextEditor(text: $memos[activeIndex])
                            .frame(width: 250, height: 200)
                            .background(Color.yellow.opacity(0.9))
                            .cornerRadius(10)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(width: geo.size.width, height: webHeight)

                HStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Button(action: {
                            sessions[activeIndex].saveCookies()
                            recentIndex = activeIndex
                            activeIndex = i
                            inputURL = sessions[i].webView.url?.absoluteString ?? "https://duckduckgo.com"
                            // 未ロードなら開く
                            if sessions[i].webView.url == nil {
                                sessions[i].loadInitialURL()
                            }
                        }) {
                            Text("\(i + 1)")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: footerHeight)
                                .background(activeIndex == i ? Color.blue.opacity(0.2) : Color.clear)
                        }
                    }
                    
                    Button(action: { showMemo.toggle() }) {
                        Image(systemName: "note.text")
                            .frame(width: footerHeight, height: footerHeight)
                            .foregroundColor(showMemo ? .orange : .primary)
                    }
                }
                .frame(height: footerHeight)
                .background(Material.thinMaterial)
            }
            .ignoresSafeArea(.all, edges: .all) // SafeAreaを完全無視してGeometryReaderに任せる
            .onAppear {
                sessions[0].loadInitialURL()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                for session in sessions {
                    session.saveCookies()
                }
            }
        }
        .ignoresSafeArea()
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
