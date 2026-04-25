import SwiftUI
import WebKit

// MARK: - TabSession
struct TabSession: Identifiable {
    let id: Int
    let userAgent: String
    let webView: WKWebView
    var memo: String = ""
    
    init(id: Int, ua: String) {
        self.id = id
        self.userAgent = ua
        let store = WKWebsiteDataStore.nonPersistent()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.customUserAgent = ua
        if let url = URL(string: "https://www.google.com") {
            self.webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var activeIndex: Int = 0
    @State private var recentIndex: Int = 0
    @State private var showMemo: Bool = false
    @State private var inputURL: String = "https://www.google.com"
    @State private var sessions: [TabSession] = [
        TabSession(id: 1, ua: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 2, ua: "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        TabSession(id: 3, ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"),
        TabSession(id: 4, ua: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"),
        TabSession(id: 5, ua: "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerArea
            
            ZStack {
                mainBrowserArea
                if showMemo {
                    memoOverlayArea
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            footerArea
        }
        .edgesIgnoringSafeArea(.bottom)
    }

    // --- 各パーツを型指定した変数に切り出すことでコンパイラを助ける ---

    @ViewBuilder
    private var headerArea: some View {
        HStack(spacing: 8) {
            Button(action: { sessions[activeIndex].webView.goBack() }) {
                Image(systemName: "chevron.left").font(.headline)
            }.frame(width: 44, height: 44)
            
            TextField("URL", text: $inputURL, onCommit: loadURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            Button(action: { sessions[activeIndex].webView.reload() }) {
                Image(systemName: "arrow.clockwise")
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 10)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var mainBrowserArea: some View {
        ForEach(0..<5, id: \.self) { index in
            if index == activeIndex || index == recentIndex {
                WebViewContainer(webView: sessions[index].webView)
                    .opacity(index == activeIndex ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private var footerArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    tabButton(for: index)
                }
                memoToggleButton
            }
            Color.clear.frame(height: safeAreaBottom)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func tabButton(for index: Int) -> some View {
        Button(action: { switchTab(to: index) }) {
            VStack(spacing: 4) {
                Text("\(index + 1)").font(.system(size: 20, weight: .bold))
                Circle()
                    .fill(activeIndex == index ? Color.blue : (recentIndex == index ? Color.blue.opacity(0.3) : Color.clear))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, height: 60)
            .background(activeIndex == index ? Color.blue.opacity(0.1) : Color.clear)
        }
    }

    @ViewBuilder
    private var memoToggleButton: some View {
        Button(action: { showMemo.toggle() }) {
            Image(systemName: "note.text")
                .font(.system(size: 20))
                .frame(width: 60, height: 60)
                .foregroundColor(showMemo ? .orange : .primary)
        }
    }

    @ViewBuilder
    private var memoOverlayArea: some View {
        VStack {
            TextEditor(text: $sessions[activeIndex].memo)
                .padding(8)
                .background(Color(.systemYellow).opacity(0.9))
                .cornerRadius(12)
                .frame(width: 280, height: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.bottom, 80).padding(.trailing, 20)
    }

    // MARK: - Helpers
    private func switchTab(to index: Int) {
        recentIndex = activeIndex
        activeIndex = index
        inputURL = sessions[activeIndex].webView.url?.absoluteString ?? ""
    }

    private func loadURL() {
        let str = inputURL.lowercased().hasPrefix("http") ? inputURL : "https://\(inputURL)"
        if let url = URL(string: str) {
            sessions[activeIndex].webView.load(URLRequest(url: url))
        }
    }

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom ?? 0
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
