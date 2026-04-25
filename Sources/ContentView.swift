import SwiftUI
import WebKit
import Combine

// MARK: - WebView
struct WebView: UIViewRepresentable {
    @ObservedObject var session: TabSession
    func makeUIView(context: Context) -> WKWebView {
        let wv = session.webView
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - TabSession
class TabSession: ObservableObject, Identifiable {
    let id: Int
    let userAgent: String
    @Published var webView: WKWebView
    @Published var currentURL: String = "https://duckduckgo.com"
    @Published var memo: String = ""
    private var cancellables = Set<AnyCancellable>()

    init(id: Int, ua: String) {
        self.id = id
        self.userAgent = ua
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() 
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = ua
        wv.allowsBackForwardNavigationGestures = true
        self.webView = wv
        loadMemo(); loadCookies(); observeURL(); loadInitial()
    }

    func loadInitial() {
        if webView.url == nil {
            let url = URL(string: "https://duckduckgo.com")!
            webView.load(URLRequest(url: url))
        }
    }

    private func observeURL() {
        webView.publisher(for: \.url)
            .compactMap { $0?.absoluteString }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.currentURL = url
                self?.saveCookies()
            }
            .store(in: &cancellables)
    }

    func saveCookies() {
        self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let arr = cookies.compactMap { cookie -> [String: Any]? in
                var dict = [String: Any]()
                for (key, value) in cookie.properties ?? [:] {
                    if let date = value as? Date { dict[key.rawValue] = date.timeIntervalSince1970 }
                    else if value is NSString || value is NSNumber { dict[key.rawValue] = value }
                }
                return dict
            }
            let url = self.tabDir().appendingPathComponent("cookies.json")
            try? JSONSerialization.data(withJSONObject: arr).write(to: url)
        }
    }

    func loadCookies() {
        let url = tabDir().appendingPathComponent("cookies.json")
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for dict in arr {
            var props = [HTTPCookiePropertyKey: Any]()
            for (key, value) in dict {
                let cookieKey = HTTPCookiePropertyKey(rawValue: key)
                if (cookieKey == .expires || key.contains("Expires")), let interval = value as? TimeInterval {
                    props[cookieKey] = Date(timeIntervalSince1970: interval)
                } else { props[cookieKey] = value }
            }
            if let cookie = HTTPCookie(properties: props) { store.setCookie(cookie) }
        }
    }

    func clearCookies() {
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                DispatchQueue.main.async { self.webView.reload() }
            }
        }
    }

    func saveMemo() { try? memo.data(using: .utf8)?.write(to: tabDir().appendingPathComponent("memo.txt")) }
    func loadMemo() { if let data = try? Data(contentsOf: tabDir().appendingPathComponent("memo.txt")) { memo = String(data: data, encoding: .utf8) ?? "" } }
    private func tabDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tabs/\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var active = 0
    @State private var showMemo = false
    @State private var showingDeleteConfirm = false
    @State private var sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // URLバー：上端の黒帯を塗りつぶす
            headerView
                .background(Color(UIColor.secondarySystemBackground).ignoresSafeArea(edges: .top))

            // メインWebView
            ZStack {
                ForEach(sessions.indices, id: \.self) { i in
                    WebView(session: sessions[i])
                        .id(sessions[i].id)
                        .opacity(i == active ? 1 : 0)
                        .allowsHitTesting(i == active)
                }
                if showMemo {
                    VStack { Spacer(); memoArea }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // タブバー：下端の黒帯を塗りつぶす
            tabBarView
                .background(Color(UIColor.secondarySystemBackground).ignoresSafeArea(edges: .bottom))
        }
        // 全体の背景
        .background(Color(UIColor.secondarySystemBackground))
        .confirmationDialog("履歴削除", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) { sessions[active].clearCookies() }
            Button("キャンセル", role: .cancel) {}
        }
    }

    var headerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 18) {
                Button(action: { sessions[active].webView.goBack() }) { Image(systemName: "chevron.left") }
                Button(action: { sessions[active].webView.goForward() }) { Image(systemName: "chevron.right") }
            }
            TextField("URL", text: $sessions[active].currentURL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .onSubmit { loadURL() }
            HStack(spacing: 18) {
                Button(action: { sessions[active].webView.reload() }) { Image(systemName: "arrow.clockwise") }
                Button(action: { showingDeleteConfirm = true }) { Image(systemName: "trash") }
                Button(action: { withAnimation { showMemo.toggle() } }) { Image(systemName: "note.text") }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8) // システムが自動的に最適な位置に置く
    }

    var tabBarView: some View {
        HStack(spacing: 0) {
            ForEach(sessions.indices, id: \.self) { i in
                Button(action: { active = i }) {
                    VStack(spacing: 4) {
                        Text("\(i+1)").bold()
                        Text(["iPhone", "iPad", "PC", "Android", "IE"][i]).font(.system(size: 8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(i == active ? Color.blue.opacity(0.1) : Color.clear)
                }
                .foregroundColor(.primary)
            }
        }
    }

    var memoArea: some View {
        TextEditor(text: $sessions[active].memo)
            .frame(height: 150)
            .cornerRadius(10)
            .padding()
            .shadow(radius: 5)
    }

    private func loadURL() {
        let text = sessions[active].currentURL.trimmingCharacters(in: .whitespaces)
        let urlStr = (text.contains(".") && !text.contains(" ")) ? (text.hasPrefix("http") ? text : "https://\(text)") : "https://duckduckgo.com/?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: urlStr) { sessions[active].webView.load(URLRequest(url: url)) }
    }
}
