import SwiftUI
import WebKit
import Combine

// MARK: - WebView

struct WebView: UIViewRepresentable {
    @ObservedObject var session: TabSession

    func makeUIView(context: Context) -> WKWebView {
        session.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // WebView差し替え対応
        if uiView !== session.webView {
            context.coordinator.replace(old: uiView, new: session.webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        func replace(old: WKWebView, new: WKWebView) {
            guard let superview = old.superview else { return }
            new.translatesAutoresizingMaskIntoConstraints = false
            superview.addSubview(new)

            NSLayoutConstraint.activate([
                new.topAnchor.constraint(equalTo: superview.topAnchor),
                new.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                new.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                new.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            ])

            old.removeFromSuperview()
        }
    }
}

// MARK: - TabSession

class TabSession: ObservableObject, Identifiable {
    let id: Int

    @Published var webView: WKWebView
    @Published var currentURL: String = "https://duckduckgo.com"
    @Published var memo: String = ""
    @Published var userAgent: String

    private var cancellables = Set<AnyCancellable>()

    init(id: Int, ua: String) {
        self.id = id
        self.userAgent = ua
        self.webView = Self.makeWebView(ua: ua)

        loadMemo()
        loadCookies()

        observeURL()
        loadInitial()
    }

    // MARK: WebView生成

    static func makeWebView(ua: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = ua
        return wv
    }

    func changeUA(_ ua: String) {
        userAgent = ua
        webView = Self.makeWebView(ua: ua)
        loadCookies()
        observeURL()
        loadInitial()
    }

    // MARK: URL

    func loadInitial() {
        if webView.url == nil {
            let url = URL(string: "https://duckduckgo.com")!
            webView.load(URLRequest(url: url))
        }
    }

    private func observeURL() {
        cancellables.removeAll()
        webView.publisher(for: \.url)
            .compactMap { $0?.absoluteString }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.currentURL = $0 }
            .store(in: &cancellables)
    }

    // MARK: Cookie

    func saveCookies() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let arr = cookies.compactMap { $0.properties }
            let url = self.tabDir().appendingPathComponent("cookies.json")
            if let json = try? JSONSerialization.data(withJSONObject: arr) {
                try? json.write(to: url)
            }
        }
    }

    func loadCookies() {
        let url = tabDir().appendingPathComponent("cookies.json")
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        for dict in arr {
            // [String: Any] を [HTTPCookiePropertyKey: Any] に変換
            var cookieProps = [HTTPCookiePropertyKey: Any]()
            for (key, value) in dict {
                cookieProps[HTTPCookiePropertyKey(rawValue: key)] = value
            }
            
            if let cookie = HTTPCookie(properties: cookieProps) {
                store.setCookie(cookie)
            }
        }
    }

    func clearCookies() {
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()

        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async {
                    self.webView.reload()
                }
            }
        }
    }

    // MARK: Memo

    func saveMemo() {
        let url = tabDir().appendingPathComponent("memo.txt")
        try? memo.data(using: .utf8)?.write(to: url)
    }

    func loadMemo() {
        let url = tabDir().appendingPathComponent("memo.txt")
        if let data = try? Data(contentsOf: url),
           let str = String(data: data, encoding: .utf8) {
            memo = str
        }
    }

    // MARK: Path

    private func tabDir() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let tabs = base.appendingPathComponent("tabs")
        let dir = tabs.appendingPathComponent("\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - ContentView

struct ContentView: View {

    @State private var active = 0
    @State private var showMemo = false

    private let sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        VStack(spacing: 0) {

            // 🔼 ヘッダー
            HStack {
                Button("<") { sessions[active].webView.goBack() }
                Button(">") { sessions[active].webView.goForward() }

                TextField("URL", text: Binding(
                    get: { sessions[active].currentURL },
                    set: { sessions[active].currentURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit { loadURL() }

                Button("⟳") { sessions[active].webView.reload() }
                Button("🗑") { sessions[active].clearCookies() }
                Button("📝") { showMemo.toggle() }

                Menu("UA") {
                    Button("iPhone") { sessions[active].changeUA(sessions[0].userAgent) }
                    Button("iPad") { sessions[active].changeUA(sessions[1].userAgent) }
                    Button("PC") { sessions[active].changeUA(sessions[2].userAgent) }
                    Button("Android") { sessions[active].changeUA(sessions[3].userAgent) }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)

            // 🌐 Web
            ZStack {
                ForEach(sessions.indices, id: \.self) { i in
                    WebView(session: sessions[i])
                        .opacity(i == active ? 1 : 0)
                }

                if showMemo {
                    VStack {
                        Spacer()
                        TextEditor(text: Binding(
                            get: { sessions[active].memo },
                            set: {
                                sessions[active].memo = $0
                                sessions[active].saveMemo()
                            }
                        ))
                        .frame(height: 200)
                        .padding()
                        .background(Color.yellow.opacity(0.9))
                        .cornerRadius(10)
                        .padding()
                    }
                }
            }

            // 🔽 タブ
            HStack {
                ForEach(sessions.indices, id: \.self) { i in
                    Button("\(i+1)") {
                        sessions[active].saveCookies()
                        sessions[active].saveMemo()
                        active = i
                    }
                    .frame(maxWidth: .infinity)
                    .background(i == active ? Color.blue.opacity(0.2) : Color.clear)
                }
            }
            .frame(height: 50)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func loadURL() {
        let text = sessions[active].currentURL
        let urlStr: String

        if text.contains(".") {
            urlStr = text.hasPrefix("http") ? text : "https://\(text)"
        } else {
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlStr = "https://duckduckgo.com/?q=\(q)"
        }

        if let url = URL(string: urlStr) {
            sessions[active].webView.load(URLRequest(url: url))
        }
    }
}
