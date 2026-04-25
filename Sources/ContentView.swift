// ContentView.swift
// 5タブ固定ブラウザ - タブごとに Cookie / UA / Proxy が完全独立
// iOS 17+ 対応
//
// ---------------------------------------------------------------
// 構成
//   TabProfile          : タブの設定値（UA・Proxy）
//   BrowserTab          : タブの実行時状態（ObservableObject）
//   BrowserViewModel    : 5タブ全体の管理（ObservableObject）
//   WebViewRepresentable: WKWebView の UIViewRepresentable ラッパー
//   Coordinator         : WKNavigationDelegate / WKUIDelegate
//   ContentView         : メイン UI（アドレスバー + WebView + タブバー）
//   TabSettingsView     : タブ設定シート（UA / Proxy / データ削除）
// ---------------------------------------------------------------

import SwiftUI
import WebKit
import Network   // ProxyConfiguration に必要

// MARK: - TabProfile（タブごとの静的設定）

struct TabProfile {
    var title: String           // タブ表示名
    var userAgent: String       // カスタム User-Agent（空文字 = デフォルト UA）
    var proxyHost: String       // Proxy ホスト名 or IP（空文字 = Proxy なし）
    var proxyPort: Int          // Proxy ポート番号
    var proxyUsername: String   // Proxy 認証ユーザー名（不要なら空文字）
    var proxyPassword: String   // Proxy 認証パスワード（不要なら空文字）

    // ---- サンプル値 ----
    // userAgent の例:
    //   iPhone Safari  : "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    //   Desktop Chrome : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    //   Googlebot      : "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
    //
    // Proxy の例:
    //   proxyHost: "192.168.1.100", proxyPort: 8080
    //   proxyHost: "proxy.example.com", proxyPort: 3128
}

// タブ番号に応じたデフォルト設定
extension TabProfile {
    static func defaultProfile(index: Int) -> TabProfile {
        TabProfile(
            title: "Tab \(index + 1)",
            userAgent: "",          // 空文字 = WKWebView デフォルト UA
            proxyHost: "",          // 空文字 = Proxy なし
            proxyPort: 8080,
            proxyUsername: "",
            proxyPassword: ""
        )
    }
}

// MARK: - BrowserTab（タブの実行時状態）

final class BrowserTab: ObservableObject, Identifiable {
    let id: Int

    // --- 設定 ---
    @Published var profile: TabProfile

    // --- ブラウザ状態 ---
    @Published var urlString: String = "https://www.google.com"
    @Published var displayURL: String = ""
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    // --- WebView 本体（タブごとに 1 インスタンス） ---
    let webView: WKWebView

    init(id: Int) {
        self.id = id
        self.profile = TabProfile.defaultProfile(index: id)
        self.webView = BrowserTab.buildWebView(profile: TabProfile.defaultProfile(index: id))
    }

    // MARK: WKWebView 生成

    /// プロファイルをもとに WKWebView を構築する。
    /// Proxy は iOS 17 以降の `proxyConfigurations` API を使用。
    static func buildWebView(profile: TabProfile) -> WKWebView {
        let config = WKWebViewConfiguration()

        // ---- DataStore: タブごとに完全独立 ----
        // nonPersistent() で永続化しない独立ストアを生成。
        // 永続化したい場合は WKWebsiteDataStore(forIdentifier:) (iOS 17+) を使用。
        config.websiteDataStore = .nonPersistent()

        // ---- Proxy 設定 (iOS 17+) ----
        if #available(iOS 17.0, *), !profile.proxyHost.isEmpty {
            var proxyConfig = ProxyConfiguration(
                httpCONNECTProxy: NWEndpoint.hostPort(
                    host: NWEndpoint.Host(profile.proxyHost),
                    port: NWEndpoint.Port(integerLiteral: UInt16(profile.proxyPort))
                )
            )
            // 認証情報がある場合のみセット
            if !profile.proxyUsername.isEmpty {
                proxyConfig.applyCredential(
                    URLCredential(
                        user: profile.proxyUsername,
                        password: profile.proxyPassword,
                        persistence: .none
                    )
                )
            }
            config.websiteDataStore.proxyConfigurations = [proxyConfig]
        }

        let webView = WKWebView(frame: .zero, configuration: config)

        // ---- User-Agent ----
        if !profile.userAgent.isEmpty {
            webView.customUserAgent = profile.userAgent
        }

        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    // MARK: Proxy / UA 変更時に WebView を再構築

    /// 設定変更後に呼び出す。新しい WKWebView を返すので呼び出し側で差し替える。
    func rebuildWebView() -> WKWebView {
        return BrowserTab.buildWebView(profile: profile)
    }

    // MARK: データ削除

    func clearData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        webView.configuration.websiteDataStore.removeData(
            ofTypes: types,
            modifiedSince: .distantPast
        ) {
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

// MARK: - BrowserViewModel（5タブ管理）

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

        // KVO でプログレス・タイトルを監視
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        tab.webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)

        loadInitialPage()
        return tab.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    private func loadInitialPage() {
        guard let url = URL(string: tab.urlString) else { return }
        tab.webView.load(URLRequest(url: url))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var tab: BrowserTab?

        init(tab: BrowserTab) {
            self.tab = tab
        }

        deinit {
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.title))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
            tab?.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard let tab else { return }
            DispatchQueue.main.async {
                switch keyPath {
                case #keyPath(WKWebView.estimatedProgress):
                    tab.estimatedProgress = tab.webView.estimatedProgress
                case #keyPath(WKWebView.title):
                    tab.pageTitle = tab.webView.title ?? ""
                case #keyPath(WKWebView.url):
                    tab.displayURL = tab.webView.url?.absoluteString ?? ""
                case #keyPath(WKWebView.canGoBack):
                    tab.canGoBack = tab.webView.canGoBack
                case #keyPath(WKWebView.canGoForward):
                    tab.canGoForward = tab.webView.canGoForward
                default:
                    break
                }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.tab?.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.tab?.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.tab?.isLoading = false }
        }

        // Proxy 認証チャレンジへの応答
        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard
                challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
                challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest,
                let tab,
                !tab.profile.proxyUsername.isEmpty
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            let credential = URLCredential(
                user: tab.profile.proxyUsername,
                password: tab.profile.proxyPassword,
                persistence: .none
            )
            completionHandler(.useCredential, credential)
        }

        // 新規ウィンドウ（target="_blank"）を同タブで開く
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

// MARK: - TabSettingsView（設定シート）

struct TabSettingsView: View {
    @ObservedObject var tab: BrowserTab
    var onApply: (BrowserTab) -> Void   // 設定適用コールバック

    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false
    @State private var showApplyAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // ---- 基本情報 ----
                Section("タブ情報") {
                    HStack {
                        Text("タブ名")
                        Spacer()
                        TextField("Tab 1", text: $tab.profile.title)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                }

                // ---- User-Agent ----
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User-Agent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $tab.profile.userAgent)
                            .frame(minHeight: 80)
                            .font(.system(.caption, design: .monospaced))
                    }
                } header: {
                    Text("User-Agent")
                } footer: {
                    Text("空欄の場合は WKWebView のデフォルト UA が使用されます。\n例: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
                        .font(.caption2)
                }

                // ---- Proxy ----
                Section {
                    HStack {
                        Text("ホスト")
                        Spacer()
                        TextField("192.168.1.100", text: $tab.profile.proxyHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("ポート")
                        Spacer()
                        TextField("8080", value: $tab.profile.proxyPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("ユーザー名")
                        Spacer()
                        TextField("任意", text: $tab.profile.proxyUsername)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("パスワード")
                        Spacer()
                        SecureField("任意", text: $tab.profile.proxyPassword)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("HTTP CONNECT Proxy (iOS 17+)")
                } footer: {
                    Text("ホストが空欄の場合は Proxy を使用しません。設定後「適用して再起動」が必要です。")
                        .font(.caption2)
                }

                // ---- データ管理 ----
                Section("データ管理") {
                    Button("このタブのデータをすべて削除") {
                        showClearAlert = true
                    }
                    .foregroundColor(.red)
                }

                // ---- 適用 ----
                Section {
                    Button("設定を適用して WebView を再起動") {
                        showApplyAlert = true
                    }
                    .bold()
                } footer: {
                    Text("UA・Proxy の変更を反映するには WebView の再構築が必要です。現在のページ履歴はリセットされます。")
                        .font(.caption2)
                }
            }
            .navigationTitle("タブ設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            // データ削除確認
            .alert("データを削除", isPresented: $showClearAlert) {
                Button("削除", role: .destructive) {
                    tab.clearData {
                        // 削除後にトップページへ戻す
                        if let url = URL(string: "about:blank") {
                            tab.webView.load(URLRequest(url: url))
                        }
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("このタブの Cookie・キャッシュ・ローカルストレージをすべて削除します。")
            }
            // 設定適用確認
            .alert("WebView を再起動", isPresented: $showApplyAlert) {
                Button("再起動", role: .destructive) {
                    onApply(tab)
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("新しい設定を適用するため WebView を再構築します。履歴・入力状態はリセットされます。")
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

    // WebView 再構築トリガー用（タブ ID -> UUID で差し替えを通知）
    @State private var webViewTokens: [Int: UUID] = Dictionary(
        uniqueKeysWithValues: (0..<BrowserViewModel.tabCount).map { ($0, UUID()) }
    )

    private var tab: BrowserTab { vm.currentTab }

    var body: some View {
        VStack(spacing: 0) {
            // ── アドレスバー ──────────────────────────────
            addressBar
                .background(.ultraThinMaterial)

            // ── プログレスバー ────────────────────────────
            if tab.isLoading {
                ProgressView(value: tab.estimatedProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(.accentColor)
            } else {
                Divider()
            }

            // ── WebView 本体 ──────────────────────────────
            // id を変更すると SwiftUI が View を再生成 → Coordinatorも再生成されてKVO再登録
            WebViewRepresentable(tab: tab)
                .id(webViewTokens[tab.id])
                .ignoresSafeArea(edges: .bottom)

            // ── タブバー ──────────────────────────────────
            tabBar
                .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $showSettings) {
            TabSettingsView(tab: tab) { updatedTab in
                applySettings(for: updatedTab)
            }
        }
    }

    // MARK: Address Bar

    private var addressBar: some View {
        HStack(spacing: 8) {
            // 戻る
            Button {
                tab.webView.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(!tab.canGoBack)

            // 進む
            Button {
                tab.webView.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(!tab.canGoForward)

            // URL フィールド
            urlField
                .frame(maxWidth: .infinity)

            // 設定
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var urlField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))

            if isEditingURL {
                TextField("URLを入力", text: $editingText, onCommit: commitURL)
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            } else {
                Button {
                    editingText = tab.displayURL
                    isEditingURL = true
                } label: {
                    Text(tab.displayURL.isEmpty ? "URLを入力" : displayHost(from: tab.displayURL))
                        .font(.system(size: 14))
                        .foregroundColor(tab.displayURL.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 10)
                }
            }
        }
        .frame(height: 36)
    }

    // MARK: Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(vm.tabs) { t in
                tabItem(t)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func tabItem(_ t: BrowserTab) -> some View {
        let isSelected = t.id == vm.selectedIndex
        return Button {
            vm.selectedIndex = t.id
            isEditingURL = false
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    // アクティブタブのインジケータ
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 28, height: 3)
                            .offset(y: -14)
                    }
                    Image(systemName: isSelected ? "globe" : "globe")
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                Text(t.profile.title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Helpers

    private func commitURL() {
        isEditingURL = false
        var raw = editingText.trimmingCharacters(in: .whitespaces)
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            // スペースが含まれる、または . がない場合は Google 検索へ
            if raw.contains(" ") || !raw.contains(".") {
                let query = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
                raw = "https://www.google.com/search?q=\(query)"
            } else {
                raw = "https://\(raw)"
            }
        }
        tab.urlString = raw
        if let url = URL(string: raw) {
            tab.webView.load(URLRequest(url: url))
        }
    }

    private func displayHost(from urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }

    /// 設定適用: WebView を再構築して新しい UA・Proxy を反映
    private func applySettings(for updatedTab: BrowserTab) {
        let idx = updatedTab.id
        // 既存の webView に新設定を反映できないため、BrowserTab を作り直す
        let newTab = BrowserTab(id: idx)
        newTab.profile = updatedTab.profile
        newTab.urlString = updatedTab.urlString

        // webView は BrowserTab.buildWebView で再構築済み
        // vm.tabs を差し替え
        vm.tabs[idx] = newTab

        // id 変更で SwiftUI が WebViewRepresentable を再生成
        webViewTokens[idx] = UUID()

        // 初期ページをロード
        if let url = URL(string: newTab.urlString) {
            newTab.webView.load(URLRequest(url: url))
        }
    }
}
