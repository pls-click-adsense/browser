// ContentView.swift
// 5タブ固定ブラウザ - タブごとに Cookie / UA / Proxy が完全独立（永続化対応版）
// iOS 17+ 対応

import SwiftUI
import WebKit
import Network
import CryptoKit // UUID生成用

// MARK: - TabProfile（タブごとの静的設定）

struct TabProfile {
    var title: String
    var userAgent: String
    var proxyHost: String
    var proxyPort: Int
    var proxyUsername: String
    var proxyPassword: String
}

extension TabProfile {
    static func defaultProfile(index: Int) -> TabProfile {
        TabProfile(
            title: "Tab \(index + 1)",
            userAgent: "",
            proxyHost: "",
            proxyPort: 8080,
            proxyUsername: "",
            proxyPassword: ""
        )
    }
}

// MARK: - BrowserTab（タブの実行時状態）

final class BrowserTab: ObservableObject, Identifiable {
    let id: Int

    @Published var profile: TabProfile
    @Published var urlString: String = "https://www.google.com"
    @Published var displayURL: String = ""
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    let webView: WKWebView

    init(id: Int) {
        self.id = id
        let defaultProfile = TabProfile.defaultProfile(index: id)
        self.profile = defaultProfile
        // 初期化時に id を渡して WebView を作成
        self.webView = BrowserTab.buildWebView(profile: defaultProfile, id: id)
    }

    /// プロファイルをもとに WKWebView を構築（永続化対応）
    static func buildWebView(profile: TabProfile, id: Int) -> WKWebView {
        let config = WKWebViewConfiguration()

        // ---- DataStore: タブごとにディスク保存領域を分離（永続化） ----
        // 固定の識別子（TabSession_0 など）を使うことで、アプリを閉じてもデータが残る
        let storeName = "TabSession_\(id)"
        // 文字列から固定のUUIDを生成
        let namespace = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")! // DNS namespace
        let data = storeName.data(using: .utf8)!
        var hash = Insecure.SHA1.hash(data: data)
        var bytes = Array(hash)
        bytes[6] = (bytes[6] & 0x0f) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3f) | 0x80 // variant 1
        let storeUUID = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeUUID)

        // ---- Proxy 設定 (iOS 17+) ----
        if #available(iOS 17.0, *), !profile.proxyHost.isEmpty {
            var proxyConfig = ProxyConfiguration(
                httpCONNECTProxy: NWEndpoint.hostPort(
                    host: NWEndpoint.Host(profile.proxyHost),
                    port: NWEndpoint.Port(integerLiteral: UInt16(profile.proxyPort))
                )
            )
            if !profile.proxyUsername.isEmpty {
                proxyConfig.applyCredential(
                    URLCredential(
                        user: profile.proxyUsername,
                        password: profile.proxyPassword,
                        persistence: .permanent // 認証情報も永続化
                    )
                )
            }
            config.websiteDataStore.proxyConfigurations = [proxyConfig]
        }

        let webView = WKWebView(frame: .zero, configuration: config)

        if !profile.userAgent.isEmpty {
            webView.customUserAgent = profile.userAgent
        }

        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func clearData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        webView.configuration.websiteDataStore.removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        ) {
            DispatchQueue.main.async { completion() }
        }
    }
}

// MARK: - BrowserViewModel

final class BrowserViewModel: ObservableObject {
    static let tabCount = 5
    @Published var tabs: [BrowserTab]
    @Published var selectedIndex: Int = 0
    var currentTab: BrowserTab { tabs[selectedIndex] }

    init() {
        tabs = (0..<BrowserViewModel.tabCount).map { BrowserTab(id: $0) }
    }
}

// MARK: - WebViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var tab: BrowserTab

    func makeUIView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        tab.webView.uiDelegate = context.coordinator

        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)

        if let url = URL(string: tab.urlString) {
            tab.webView.load(URLRequest(url: url))
        }
        return tab.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var tab: BrowserTab?
        init(tab: BrowserTab) { self.tab = tab }

        deinit {
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.title))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard let tab = tab else { return }
            DispatchQueue.main.async {
                switch keyPath {
                case #keyPath(WKWebView.estimatedProgress): tab.estimatedProgress = tab.webView.estimatedProgress
                case #keyPath(WKWebView.title): tab.pageTitle = tab.webView.title ?? ""
                case #keyPath(WKWebView.url): tab.displayURL = tab.webView.url?.absoluteString ?? ""
                case #keyPath(WKWebView.canGoBack): tab.canGoBack = tab.webView.canGoBack
                case #keyPath(WKWebView.canGoForward): tab.canGoForward = tab.webView.canGoForward
                default: break
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.tab?.isLoading = true }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.tab?.isLoading = false }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.tab?.isLoading = false }
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}

// MARK: - TabSettingsView

struct TabSettingsView: View {
    @ObservedObject var tab: BrowserTab
    var onApply: (BrowserTab) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false
    @State private var showApplyAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("タブ情報") {
                    HStack {
                        Text("タブ名")
                        Spacer()
                        TextField("Tab 1", text: $tab.profile.title).multilineTextAlignment(.trailing).foregroundColor(.secondary)
                    }
                }
                Section("User-Agent") {
                    TextEditor(text: $tab.profile.userAgent).frame(minHeight: 80).font(.system(.caption, design: .monospaced))
                }
                Section("Proxy (iOS 17+)") {
                    HStack { Text("ホスト"); Spacer(); TextField("192.168.1.100", text: $tab.profile.proxyHost).multilineTextAlignment(.trailing) }
                    HStack { Text("ポート"); Spacer(); TextField("8080", value: $tab.profile.proxyPort, format: .number).multilineTextAlignment(.trailing).keyboardType(.numberPad) }
                    HStack { Text("ユーザー名"); Spacer(); TextField("任意", text: $tab.profile.proxyUsername).multilineTextAlignment(.trailing) }
                    HStack { Text("パスワード"); Spacer(); SecureField("任意", text: $tab.profile.proxyPassword).multilineTextAlignment(.trailing) }
                }
                Section { Button("データをすべて削除") { showClearAlert = true }.foregroundColor(.red) }
                Section { Button("設定を適用して再起動") { showApplyAlert = true }.bold() }
            }
            .navigationTitle("タブ設定")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .alert("データを削除", isPresented: $showClearAlert) {
                Button("削除", role: .destructive) { tab.clearData { tab.webView.load(URLRequest(url: URL(string: "about:blank")!)) } }
            }
            .alert("再起動しますか？", isPresented: $showApplyAlert) {
                Button("再起動", role: .destructive) { onApply(tab); dismiss() }
            }
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = BrowserViewModel()
    @State private var showSettings = false
    @State private var isEditingURL = false
    @State private var editingText = ""
    @State private var webViewTokens: [Int: UUID] = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, UUID()) })

    var body: some View {
        VStack(spacing: 0) {
            addressBar.background(.ultraThinMaterial)
            if vm.currentTab.isLoading {
                ProgressView(value: vm.currentTab.estimatedProgress).progressViewStyle(.linear).frame(height: 2)
            } else { Divider() }

            WebViewRepresentable(tab: vm.currentTab)
                .id(webViewTokens[vm.selectedIndex])
                .ignoresSafeArea(edges: .bottom)

            tabBar.background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSettings) {
            TabSettingsView(tab: vm.currentTab) { updatedTab in
                let idx = updatedTab.id
                let newTab = BrowserTab(id: idx)
                newTab.profile = updatedTab.profile
                newTab.urlString = updatedTab.urlString
                vm.tabs[idx] = newTab
                webViewTokens[idx] = UUID()
            }
        }
    }

    private var addressBar: some View {
        HStack {
            Button(action: { vm.currentTab.webView.goBack() }) { Image(systemName: "chevron.left") }.disabled(!vm.currentTab.canGoBack)
            Button(action: { vm.currentTab.webView.goForward() }) { Image(systemName: "chevron.right") }.disabled(!vm.currentTab.canGoForward)
            
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6))
                if isEditingURL {
                    TextField("URLを入力", text: $editingText, onCommit: commitURL)
                        .padding(.horizontal, 10).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                } else {
                    Button(action: { editingText = vm.currentTab.displayURL; isEditingURL = true }) {
                        Text(vm.currentTab.displayURL.isEmpty ? "URLを入力" : (URL(string: vm.currentTab.displayURL)?.host ?? vm.currentTab.displayURL))
                            .font(.system(size: 14)).lineLimit(1).padding(.horizontal, 10)
                    }
                }
            }.frame(height: 36)

            Button(action: { showSettings = true }) { Image(systemName: "slider.horizontal.3") }
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(vm.tabs) { t in
                Button(action: { vm.selectedIndex = t.id; isEditingURL = false }) {
                    VStack(spacing: 3) {
                        Image(systemName: "globe").font(.system(size: 22))
                        Text(t.profile.title).font(.system(size: 9))
                    }
                    .foregroundColor(t.id == vm.selectedIndex ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }.padding(.vertical, 6)
    }

    private func commitURL() {
        isEditingURL = false
        var raw = editingText.trimmingCharacters(in: .whitespaces)
        if !raw.hasPrefix("http") {
            if raw.contains(" ") || !raw.contains(".") {
                raw = "https://www.google.com/search?q=\(raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw)"
            } else { raw = "https://\(raw)" }
        }
        vm.currentTab.urlString = raw
        if let url = URL(string: raw) { vm.currentTab.webView.load(URLRequest(url: url)) }
    }
}
