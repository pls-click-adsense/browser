import SwiftUI
import WebKit
import Combine

// MARK: - WebView
struct WebView: UIViewRepresentable {
    @ObservedObject var session: TabSession

    func makeUIView(context: Context) -> WKWebView {
        return session.webView
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
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.webView = wv

        loadMemo()
        loadCookies()
        observeURL()
        loadInitial()
    }

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
            .sink { [weak self] url in
                self?.currentURL = url
                self?.saveCookies()
            }
            .store(in: &cancellables)
    }

    // --- Cookie Handling ---
    func saveCookies() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let arr = cookies.compactMap { cookie -> [String: Any]? in
                    var dict = [String: Any]()
                    for (key, value) in cookie.properties ?? [:] {
                        dict[key.rawValue] = value
                    }
                    return dict
                }
                let url = self.tabDir().appendingPathComponent("cookies.json")
                if let json = try? JSONSerialization.data(withJSONObject: arr) {
                    try? json.write(to: url)
                }
            }
        }
    }

    func loadCookies() {
        let url = tabDir().appendingPathComponent("cookies.json")
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()

        for dict in arr {
            var props = [HTTPCookiePropertyKey: Any]()
            for (key, value) in dict {
                props[HTTPCookiePropertyKey(rawValue: key)] = value
            }
            if let cookie = HTTPCookie(properties: props) {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
        }
        group.notify(queue: .main) {
            self.webView.reload()
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

    // --- Persistence ---
    func saveMemo() {
        let url = tabDir().appendingPathComponent("memo.txt")
        try? memo.data(using: .utf8)?.write(to: url)
    }

    func loadMemo() {
        let url = tabDir().appendingPathComponent("memo.txt")
        if let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) {
            memo = str
        }
    }

    private func tabDir() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("tabs").appendingPathComponent("\(id)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Main View
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
            // ヘッダー
            HStack(spacing: 12) {
                HStack(spacing: 16) {
                    Button(action: { sessions[active].webView.goBack() }) { Image(systemName: "chevron.left") }
                    Button(action: { sessions[active].webView.goForward() }) { Image(systemName: "chevron.right") }
                }
                TextField("URL", text: Binding(get: { sessions[active].currentURL }, set: { sessions[active].currentURL = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { loadURL() }
                HStack(spacing: 16) {
                    Button(action: { sessions[active].webView.reload() }) { Image(systemName: "arrow.clockwise") }
                    Button(action: { sessions[active].clearCookies() }) { Image(systemName: "trash") }
                    Button(action: { showMemo.toggle() }) { Image(systemName: "note.text") }
                }
            }
            .padding(10).background(.ultraThinMaterial)

            // Web表示
            ZStack {
                ForEach(sessions.indices, id: \.self) { i in
                    WebView(session: sessions[i])
                        .id(sessions[i].id)
                        .opacity(i == active ? 1 : 0)
                        .allowsHitTesting(i == active)
                }
                if showMemo {
                    VStack {
                        Spacer()
                        TextEditor(text: Binding(get: { sessions[active].memo }, set: { sessions[active].memo = $0; sessions[active].saveMemo() }))
                            .frame(height: 200).padding(8).background(Color(UIColor.secondarySystemBackground)).cornerRadius(12).padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // タブバー
            HStack(spacing: 0) {
                ForEach(sessions.indices, id: \.self) { i in
                    Button(action: { sessions[active].saveCookies(); sessions[active].saveMemo(); active = i }) {
                        VStack {
                            Text("\(i+1)").bold()
                            Text(["iPhone", "iPad", "PC", "Android", "IE"][i]).font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(i == active ? Color.blue.opacity(0.15) : Color.clear)
                    }
                }
            }
            .frame(height: 60).background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func loadURL() {
        let text = sessions[active].currentURL.trimmingCharacters(in: .whitespaces)
        let urlStr = (text.contains(".") && !text.contains(" ")) ? (text.hasPrefix("http") ? text : "https://\(text)") : "https://duckduckgo.com/?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: urlStr) { sessions[active].webView.load(URLRequest(url: url)) }
    }
}
