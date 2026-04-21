import SwiftUI

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
    
    // 安価リンク装飾
    var attributedBody: AttributedString {
        var attrString = AttributedString(body)
        let pattern = ">>(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attrString }
        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, options: [], range: range)
        for match in matches.reversed() {
            guard let resRange = Range(match.range, in: attrString),
                  let numRange = Range(match.range(at: 1), in: body) else { continue }
            attrString[resRange].link = URL(string: "anka://\(body[numRange])")
            attrString[resRange].foregroundColor = .blue
            attrString[resRange].underlineStyle = .single
        }
        return attrString
    }
    
    // Imgur画像抽出
    var imageUrls: [URL] {
        let pattern = "https?://(?:i\\.)?imgur\\.com/([a-zA-Z0-9]+)(?:\\.[a-z]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, options: [], range: range)
        return matches.compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: body) else { return nil }
            return URL(string: "https://i.imgur.com/\(body[idRange]).jpg")
        }
    }
}

enum SortOption: String, CaseIterable {
    case ikioi = "勢い順"
    case resCount = "レス数順"
    case new = "新着順"
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
    let baseURL = "https://bbs.eddibb.cc/liveedge/"
    
    func fetchThreadList() async {
        isFetching = true
        guard let url = URL(string: baseURL + "subject.txt") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = data.sjisString else { return }
            let now = Date().timeIntervalSince1970
            self.rawThreads = text.components(separatedBy: .newlines).compactMap { line in
                let parts = line.components(separatedBy: "<>")
                if parts.count < 2 { return nil }
                let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                guard let timestamp = Double(datId) else { return nil }
                let pattern = "(.*) \\((\\d+)\\)$"
                let regex = try? NSRegularExpression(pattern: pattern)
                let match = regex?.firstMatch(in: parts[1], range: NSRange(parts[1].startIndex..., in: parts[1]))
                let title = match.map { String(parts[1][Range($0.range(at: 1), in: parts[1])!]) } ?? parts[1]
                let count = match.map { Int(parts[1][Range($0.range(at: 2), in: parts[1])!]) ?? 0 } ?? 0
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
        guard let url = URL(string: baseURL + "dat/\(datId).dat") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = data.sjisString else { return }
            self.posts = text.components(separatedBy: .newlines).enumerated().compactMap { i, line in
                let p = line.components(separatedBy: "<>")
                if p.count < 4 { return nil }
                let name = p[0].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                let body = p[3].replacingOccurrences(of: "<br>", with: "\n")
                    .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&amp;", with: "&")
                return Post(id: i + 1, name: name, mail: p[1], dateAndId: p[2], body: body)
            }
            var counts: [String: Int] = [:]
            for p in self.posts { if let id = extractID(from: p.dateAndId) { counts[id, default: 0] += 1 } }
            self.idCounts = counts
        } catch { print(error) }
        isFetching = false
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
        guard let id = extractID(from: p.dateAndId) else { return (0, 0) }
        let total = idCounts[id] ?? 0
        let current = posts.prefix(p.id).filter { extractID(from: $0.dateAndId) == id }.count
        return (current, total)
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject var viewModel = BBSViewModel()
    var body: some View {
        NavigationStack {
            List(viewModel.threads) { t in
                NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: t)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title).font(.subheadline).lineLimit(2).multilineTextAlignment(.leading)
                        HStack {
                            Text("res: \(t.resCount)").foregroundColor(.secondary)
                            Text("勢い: \(Int(t.ikioi))").foregroundColor(.red)
                            Spacer()
                            Text(Date(timeIntervalSince1970: t.createdAt), style: .time).foregroundColor(.secondary)
                        }.font(.caption2)
                    }.padding(.vertical, 2)
                }
            }
            .navigationTitle("liveedge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("ソート", selection: $viewModel.sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .refreshable { await viewModel.fetchThreadList() }
            .onAppear { if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } } }
        }
    }
}

// MARK: - Detail View
struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    @State private var selectedID: String? = nil
    @State private var targetRes: Post? = nil
    @State private var zoomImageURL: URL? = nil
    
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
            Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                if viewModel.isFetching { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
        }
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            IDFilteredView(id: idObj.id, viewModel: viewModel)
        }
        .sheet(item: $targetRes) { post in
            VStack(alignment: .leading) {
                Capsule().frame(width: 40, height: 6).foregroundColor(.secondary).padding(.top, 8).frame(maxWidth: .infinity)
                PostRow(post: post, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { zoomImageURL = $0 })
                    .padding()
                Spacer()
            }.presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: Binding(get: { zoomImageURL.map { IdentifiableURL(url: $0) } }, set: { zoomImageURL = $0?.url })) { urlObj in
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: urlObj.url) { i in i.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() }
            }
            .onTapGesture { zoomImageURL = nil }
        }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
}

// MARK: - Row Component
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
            HStack(alignment: .top, spacing: 4) {
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
            
            Text(post.attributedBody)
                .font(.body).textSelection(.enabled).padding(.leading, 24)
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
        }.padding(.vertical, 4)
    }
}

// MARK: - Helpers
struct IdentifiableID: Identifiable { let id: String }
struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }
extension Data {
    var sjisString: String? {
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: self, encoding: enc)
    }
}

struct IDFilteredView: View {
    let id: String
    let viewModel: BBSViewModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == id }) { p in
                PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { _ in })
            }
            .navigationTitle("ID:\(id)").toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
