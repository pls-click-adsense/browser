import SwiftUI
import WebKit

// MARK: - Constants
struct AppConfig {
    static let customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let boardURL = "https://bbs.eddibb.cc/liveedge/"
    static let postURL = "https://bbs.eddibb.cc/test/bbs.cgi"
}

// MARK: - HTML Decoder (Common)
func decodeHTMLEntities(_ text: String) -> String {
    var decoded = text
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
    let pattern = "&#(\\d+);"
    let regex = try? NSRegularExpression(pattern: pattern)
    let matches = regex?.matches(in: decoded, options: [], range: NSRange(decoded.startIndex..., in: decoded)) ?? []
    for match in matches.reversed() {
        if let codeRange = Range(match.range(at: 1), in: decoded),
           let codePoint = UInt32(decoded[codeRange]),
           let scalar = UnicodeScalar(codePoint) {
            decoded.replaceSubrange(Range(match.range, in: decoded)!, with: String(scalar))
        }
    }
    return decoded
}

// MARK: - Models
struct Thread: Identifiable {
    let id: String
    let title: String
    let resCount: Int
    let ikioi: Double
    let createdAt: Double
}

struct Post: Identifiable {
    let id: Int
    let name: String
    let mail: String
    let dateAndId: String
    let body: String
    
    var attributedBody: AttributedString {
        let cleanBody = decodeHTMLEntities(body)
        var attrString = AttributedString(cleanBody)
        let pattern = ">>(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attrString }
        let matches = regex.matches(in: cleanBody, options: [], range: NSRange(cleanBody.startIndex..., in: cleanBody))
        for match in matches.reversed() {
            guard let resRange = Range(match.range, in: attrString),
                  let numRange = Range(match.range(at: 1), in: cleanBody) else { continue }
            attrString[resRange].link = URL(string: "anka://\(cleanBody[numRange])")
            attrString[resRange].foregroundColor = .blue
        }
        return attrString
    }
    
    var imageUrls: [URL] {
        let pattern = "https?://(?:i\\.)?imgur\\.com/([a-zA-Z0-9]+)(?:\\.[a-z]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: body, options: [], range: NSRange(body.startIndex..., in: body))
        return matches.compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: body) else { return nil }
            return URL(string: "https://i.imgur.com/\(body[idRange]).jpg")
        }
    }
}

// MARK: - WebView
struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.customUserAgent = AppConfig.customUserAgent
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}

// MARK: - ViewModel
@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var idCounts: [String: Int] = [:]
    @Published var isFetching = false
    @Published var sortOption: SortOption = .ikioi { didSet { applySort() } }
    
    private var rawThreads: [Thread] = []
    
    func fetchThreadList() async {
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "subject.txt") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = data.sjisString else { return }
            let now = Date().timeIntervalSince1970
            self.rawThreads = text.components(separatedBy: .newlines).compactMap { line in
                let parts = line.components(separatedBy: "<>")
                if parts.count < 2 { return nil }
                let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                guard let timestamp = Double(datId) else { return nil }
                
                let titleLine = parts[1]
                let parts2 = titleLine.components(separatedBy: " (")
                let countStr = parts2.last?.replacingOccurrences(of: ")", with: "") ?? "0"
                let rawTitle = parts2.dropLast().joined(separator: " (")
                
                // スレタイのHTML実体参照（絵文字など）をデコード
                let title = decodeHTMLEntities(rawTitle)
                
                let count = Int(countStr) ?? 0
                let hours = max((now - timestamp) / 3600, 0.1)
                return Thread(id: datId, title: title, resCount: count, ikioi: Double(count)/hours, createdAt: timestamp)
            }
            applySort()
        } catch { print(error) }
        isFetching = false
    }
    
    func applySort() {
        switch sortOption {
        case .ikioi: threads = rawThreads.sorted { $0.ikioi > $1.ikioi }
        case .resCount: threads = rawThreads.sorted { $0.resCount > $1.resCount }
        case .new: threads = rawThreads.sorted { $0.createdAt > $1.createdAt }
        }
    }
    
    func fetchPosts(datId: String) async {
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "dat/\(datId).dat") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = data.sjisString else { return }
            self.posts = text.components(separatedBy: .newlines).enumerated().compactMap { i, line in
                let p = line.components(separatedBy: "<>")
                if p.count < 4 { return nil }
                let name = p[0].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                let body = p[3].replacingOccurrences(of: "<br>", with: "\n")
                return Post(id: i + 1, name: name, mail: p[1], dateAndId: p[2], body: body)
            }
            var counts: [String: Int] = [:]
            for p in self.posts { if let id = extractID(from: p.dateAndId) { counts[id, default: 0] += 1 } }
            self.idCounts = counts
        } catch { print(error) }
        isFetching = false
    }
    
    func postReply(threadId: String, name: String, mail: String, body: String) async -> (isSuccess: Bool, message: String) {
        guard let url = URL(string: AppConfig.postURL) else { return (false, "URL Error") }
        func sjisEnc(_ str: String) -> String {
            let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
            return str.data(using: enc)?.map { String(format: "%%%02X", $0) }.joined() ?? ""
        }
        let params = [("bbs","liveedge"),("key",threadId),("FROM",name),("mail",mail),("MESSAGE",body),("submit","書き込む")]
        let bodyStr = params.map { "\($0)=\(sjisEnc($1))" }.joined(separator: "&")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyStr.data(using: .ascii)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("\(AppConfig.boardURL)\(threadId)", forHTTPHeaderField: "Referer")
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            let text = data.sjisString ?? ""
            if text.contains("書き込みました") || text.contains("正常に") {
                await fetchPosts(datId: threadId)
                return (true, text)
            }
            return (false, "Status: \((res as? HTTPURLResponse)?.statusCode ?? 0)\n\(text)")
        } catch { return (false, error.localizedDescription) }
    }
    
    func extractID(from str: String) -> String? {
        let pattern = "ID:([^\\s]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        if let m = regex?.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            return String(str[Range(m.range(at: 1), in: str)!])
        }
        return nil
    }

    func getIDStats(for p: Post) -> (current: Int, total: Int) {
        guard let id = extractID(from: p.dateAndId) else { return (1, 1) }
        let currentCount = posts.prefix(p.id).filter { extractID(from: $0.dateAndId) == id }.count
        return (currentCount, idCounts[id] ?? 0)
    }

    func clearWebData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0))
    }
}

// MARK: - Views
struct ContentView: View {
    @StateObject var viewModel = BBSViewModel()
    @State private var isShowingBrowser = false
    @State private var isShowingClearAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("🛠 設定・認証") {
                    Button(action: { isShowingBrowser = true }) {
                        Label("独立認証ブラウザを開く", systemImage: "safari.fill").bold()
                    }
                    Button(role: .destructive, action: { isShowingClearAlert = true }) {
                        Label("キャッシュ・Cookie削除", systemImage: "trash")
                    }
                }
                Section("📜 スレッド一覧") {
                    ForEach(viewModel.threads) { t in
                        NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: t)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.title).font(.subheadline).fontWeight(.medium).lineLimit(2)
                                HStack {
                                    Label("\(t.resCount)", systemImage: "bubble.right").foregroundColor(.secondary)
                                    Label("\(Int(t.ikioi))", systemImage: "bolt.fill").foregroundColor(t.ikioi > 500 ? .red : .orange)
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: t.createdAt), style: .time).foregroundColor(.secondary)
                                }.font(.caption2)
                            }.padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("liveedge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("ソート", selection: $viewModel.sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .alert("削除確認", isPresented: $isShowingClearAlert) {
                Button("削除", role: .destructive) { Task { await viewModel.clearWebData() } }
                Button("キャンセル", role: .cancel) {}
            } message: { Text("認証情報をリセットしますか？") }
            .sheet(isPresented: $isShowingBrowser) {
                NavigationStack {
                    WebView(url: URL(string: AppConfig.boardURL)!)
                        .navigationTitle("認証用ブラウザ").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { isShowingBrowser = false } } }
                }
            }
            .refreshable { await viewModel.fetchThreadList() }
            .onAppear { if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } } }
        }
    }
}

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    @State private var selectedID: String? = nil
    @State private var targetRes: Post? = nil
    @State private var zoomImageURL: URL? = nil
    @State private var isShowingPostView = false
    
    var body: some View {
        List(viewModel.posts) { post in
            PostRow(post: post, viewModel: viewModel, 
                    onIDTap: { selectedID = $0 }, 
                    onAnkaTap: { num in targetRes = viewModel.posts.first { $0.id == num } },
                    onImageTap: { zoomImageURL = $0 })
        }
        .listStyle(.plain)
        .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                    if viewModel.isFetching { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { isShowingPostView = true }) {
                Image(systemName: "pencil.circle.fill").resizable().frame(width: 56, height: 56)
                    .foregroundColor(.blue).background(Color.white.clipShape(Circle())).shadow(radius: 4)
            }.padding(24)
        }
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            NavigationStack {
                List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == idObj.id }) { p in
                    PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { _ in })
                }
                .navigationTitle("ID:\(idObj.id)").toolbar { Button("閉じる") { selectedID = nil } }
            }
        }
        .sheet(item: $targetRes) { post in
            VStack {
                Capsule().frame(width: 40, height: 6).foregroundColor(.secondary).padding(.top, 8)
                PostRow(post: post, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { zoomImageURL = $0 }).padding()
                Spacer()
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingPostView) { PostView(viewModel: viewModel, threadId: thread.id) }
        .fullScreenCover(item: Binding(get: { zoomImageURL.map { IdentifiableURL(url: $0) } }, set: { zoomImageURL = $0?.url })) { urlObj in
            ZStack { Color.black.ignoresSafeArea(); AsyncImage(url: urlObj.url) { i in i.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() } }
            .onTapGesture { zoomImageURL = nil }
        }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
}

struct PostRow: View {
    let post: Post
    let viewModel: BBSViewModel
    let onIDTap: (String) -> Void
    let onAnkaTap: (Int) -> Void
    let onImageTap: (URL) -> Void
    var body: some View {
        let stats = viewModel.getIDStats(for: post)
        let idString = viewModel.extractID(from: post.dateAndId) ?? "???"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(post.id)").bold().foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.name).foregroundColor(.green).bold()
                    HStack {
                        Button(action: { onIDTap(idString) }) { Text("ID:\(idString)").underline() }.buttonStyle(.plain)
                        Text("(\(stats.current)/\(stats.total))").foregroundColor(stats.total >= 5 ? .red : .secondary)
                        Text(post.dateAndId.components(separatedBy: " ID:")[0])
                    }.font(.caption2).foregroundColor(.secondary)
                }
            }.font(.caption)
            Text(post.attributedBody).font(.body).textSelection(.enabled).padding(.leading, 24)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "anka", let num = Int(url.host ?? "") { onAnkaTap(num); return .handled }
                    return .systemAction
                })
            if !post.imageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(post.imageUrls, id: \.self) { url in
                            Button(action: { onImageTap(url) }) {
                                AsyncImage(url: url) { i in i.resizable().aspectRatio(contentMode: .fill).frame(width: 120, height: 120).cornerRadius(8) } placeholder: { ProgressView().frame(width: 120, height: 120) }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.leading, 24)
                }
            }
        }
    }
}

struct PostView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BBSViewModel
    let threadId: String
    @State private var name = ""
    @State private var mail = ""
    @State private var bodyText = ""
    @State private var resultMessage: String? = nil
    @State private var isShowingError = false
    @State private var isSending = false
    var body: some View {
        NavigationStack {
            Form {
                Section("名前 / メール") { TextField("名前", text: $name); TextField("メール", text: $mail) }
                Section("本文") { TextEditor(text: $bodyText).frame(minHeight: 150) }
            }
            .navigationTitle("レスを書く").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSending { ProgressView() } else {
                        Button("書き込む") {
                            Task {
                                isSending = true
                                let res = await viewModel.postReply(threadId: threadId, name: name, mail: mail, body: bodyText)
                                isSending = false
                                if res.isSuccess { name = ""; mail = ""; bodyText = ""; dismiss() }
                                else { resultMessage = res.message; isShowingError = true }
                            }
                        }.disabled(bodyText.isEmpty)
                    }
                }
            }
            .alert("エラー", isPresented: $isShowingError) { Button("OK"){} } message: { Text(resultMessage ?? "") }
        }
    }
}

// MARK: - Helpers
enum SortOption: String, CaseIterable { case ikioi = "🔥 勢い順", resCount = "📊 レス数順", new = "✨ 新着順" }
struct IdentifiableID: Identifiable { let id: String }
struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }
extension Data {
    var sjisString: String? {
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: self, encoding: enc)
    }
}
