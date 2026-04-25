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
// UIKitのBrowserViewControllerをSwiftUIからラップするだけ

struct ContentView: View {
    private let sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        BrowserViewControllerRepresentable(sessions: sessions)
            .ignoresSafeArea()
    }
}

// MARK: - UIViewControllerRepresentable

struct BrowserViewControllerRepresentable: UIViewControllerRepresentable {
    let sessions: [TabSession]

    func makeUIViewController(context: Context) -> BrowserViewController {
        BrowserViewController(sessions: sessions)
    }

    func updateUIViewController(_ uiViewController: BrowserViewController, context: Context) {}
}
