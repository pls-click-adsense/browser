import SwiftUI
import WebKit
import Combine

// MARK: - WebView

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - TabSession

class TabSession: ObservableObject, Identifiable {
    let id: Int
    let webView: WKWebView

    @Published var currentURL: String = "https://duckduckgo.com"
    @Published var memo: String = ""

    private var cancellables = Set<AnyCancellable>()

    init(id: Int, ua: String) {
        self.id = id

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = ua
        self.webView = wv

        // 🔹 メモ読み込み
        self.memo = UserDefaults.standard.string(forKey: "memo_\(id)") ?? ""

        // URL監視
        webView.publisher(for: \.url)
            .compactMap { $0?.absoluteString }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.currentURL = url
            }
            .store(in: &cancellables)
    }

    func loadInitial() {
        if webView.url == nil {
            webView.load(URLRequest(url: URL(string: "https://duckduckgo.com")!))
        }
    }

    func saveMemo() {
        UserDefaults.standard.set(memo, forKey: "memo_\(id)")
    }
}

// MARK: - ContentView

struct ContentView: View {

    @State private var activeIndex = 0
    @State private var showMemo = false

    private let sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone...)"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad...)"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Mac...)"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Android...)"),
        TabSession(id: 5, ua: "Mozilla/5.0 (MSIE...)")
    ]

    var body: some View {
        VStack(spacing: 0) {

            // 🔼 ヘッダー
            HStack {
                Button("<") {
                    sessions[activeIndex].webView.goBack()
                }

                Button(">") {
                    sessions[activeIndex].webView.goForward()
                }

                TextField("URL", text: Binding(
                    get: { sessions[activeIndex].currentURL },
                    set: { sessions[activeIndex].currentURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    loadURL(sessions[activeIndex].currentURL)
                }

                Button("⟳") {
                    sessions[activeIndex].webView.reload()
                }

                Button("📝") {
                    showMemo.toggle()
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)

            // 🌐 Web
            ZStack {
                ForEach(sessions.indices, id: \.self) { i in
                    WebView(webView: sessions[i].webView)
                        .opacity(i == activeIndex ? 1 : 0)
                }

                // 📝 メモ
                if showMemo {
                    VStack {
                        Spacer()
                        TextEditor(text: Binding(
                            get: { sessions[activeIndex].memo },
                            set: {
                                sessions[activeIndex].memo = $0
                                sessions[activeIndex].saveMemo() // ←保存
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
                        activeIndex = i
                        sessions[i].loadInitial()
                    }
                    .frame(maxWidth: .infinity)
                    .background(i == activeIndex ? Color.blue.opacity(0.2) : Color.clear)
                }
            }
            .frame(height: 50)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            sessions[0].loadInitial()
        }
    }

    private func loadURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let urlString: String

        if trimmed.contains(".") {
            urlString = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        } else {
            let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlString = "https://duckduckgo.com/?q=\(q)"
        }

        if let url = URL(string: urlString) {
            sessions[activeIndex].webView.load(URLRequest(url: url))
        }
    }
}
