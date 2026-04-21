import SwiftUI

// MARK: - Models
struct Thread: Identifiable {
    let id: String // datファイル名
    let title: String
    let resCount: String
}

struct Post: Identifiable {
    let id: Int
    let name: String
    let mail: String
    let dateAndId: String
    let body: String
}

struct IdentifiableID: Identifiable {
    let id: String
}

// MARK: - Data Extensions
extension Data {
    var sjisString: String? {
        // CP932 (Windows-31J) でデコード
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: self, encoding: encoding)
    }
}

// MARK: - ViewModel
@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var idCounts: [String: Int] = [:]
    @Published var isFetching = false
    
    let baseURL = "https://bbs.eddibb.cc/liveedge/"
    
    // 板のスレ一覧取得
    func fetchThreadList() async {
        isFetching = true
        guard let url = URL(string: baseURL + "subject.txt") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rawText = data.sjisString else { return }
            
            let lines = rawText.components(separatedBy: .newlines)
            self.threads = lines.compactMap { line in
                let parts = line.components(separatedBy: "<>")
                guard parts.count >= 2 else { return nil }
                let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                
                let titlePart = parts[1]
                let pattern = "(.*) \\((\\d+)\\)$"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: titlePart, range: NSRange(titlePart.startIndex..., in: titlePart)) {
                    let title = String(titlePart[Range(match.range(at: 1), in: titlePart)!])
                    let count = String(titlePart[Range(match.range(at: 2), in: titlePart)!])
                    return Thread(id: datId, title: title, resCount: count)
                }
                return Thread(id: datId, title: titlePart, resCount: "?")
            }
        } catch { print(error) }
        isFetching = false
    }
    
    // スレのレス取得
    func fetchPosts(datId: String) async {
        isFetching = true
        guard let url = URL(string: baseURL + "dat/\(datId).dat") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rawText = data.sjisString else { return }
            
            let lines = rawText.components(separatedBy: .newlines)
            let newPosts: [Post] = lines.enumerated().compactMap { index, line in
                let parts = line.components(separatedBy: "<>")
                guard parts.count >= 4 else { return nil }
                
                // 名前欄のHTMLタグ除去
                let cleanName = parts[0].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                // 本文の整形
                let cleanBody = parts[3]
                    .replacingOccurrences(of: "<br>", with: "\n")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&amp;", with: "&")
                
                return Post(id: index + 1, name: cleanName, mail: parts[1], dateAndId: parts[2], body: cleanBody)
            }
            
            self.posts = newPosts
            
            // IDカウント計算
            var counts: [String: Int] = [:]
            for post in newPosts {
                if let id = extractID(from: post.dateAndId) {
                    counts[id, default: 0] += 1
                }
            }
            self.idCounts = counts
        } catch { print(error) }
        isFetching = false
    }
    
    func extractID(from str: String) -> String? {
        let pattern = "ID:([^\\s]+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            return String(str[Range(match.range(at: 1), in: str)!])
        }
        return nil
    }
    
    func getIDStats(for post: Post) -> (current: Int, total: Int) {
        guard let id = extractID(from: post.dateAndId) else { return (0, 0) }
        let total = idCounts[id] ?? 0
        let current = posts.prefix(post.id).filter { extractID(from: $0.dateAndId) == id }.count
        return (current, total)
    }
}

// MARK: - UI Views
struct ContentView: View {
    @StateObject var viewModel = BBSViewModel()
    
    var body: some View {
        NavigationStack {
            List(viewModel.threads) { thread in
                NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: thread)) {
                    HStack {
                        Text(thread.title).lineLimit(1).font(.subheadline)
                        Spacer()
                        Text(thread.resCount).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("エッヂ liveedge")
            .refreshable { await viewModel.fetchThreadList() }
            .onAppear { if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } } }
        }
    }
}

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    @State private var selectedID: String? = nil
    
    var body: some View {
        List(viewModel.posts) { post in
            PostRow(post: post, viewModel: viewModel) { id in
                selectedID = id
            }
        }
        .listStyle(.plain)
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                    if viewModel.isFetching { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .sheet(item: Binding(
            get: { selectedID.map { IdentifiableID(id: $0) } },
            set: { selectedID = $0?.id }
        )) { identID in
            IDFilteredView(id: identID.id, viewModel: viewModel)
        }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
}

struct PostRow: View {
    let post: Post
    let viewModel: BBSViewModel
    let onIDTap: (String) -> Void
    
    var body: some View {
        let stats = viewModel.getIDStats(for: post)
        let idString = viewModel.extractID(from: post.dateAndId) ?? "???"
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                Text("\(post.id)").bold().foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.name).foregroundColor(.green).bold()
                    HStack {
                        Button(action: { onIDTap(idString) }) {
                            Text("ID:\(idString)").underline()
                        }
                        .buttonStyle(.plain)
                        Text("(\(stats.current)/\(stats.total))")
                            .foregroundColor(stats.total >= 5 ? .red : .secondary)
                        Text(post.dateAndId.components(separatedBy: " ID:")[0])
                    }
                    .font(.caption2).foregroundColor(.secondary)
                }
            }
            .font(.caption)
            
            Text(post.body)
                .font(.body)
                .textSelection(.enabled)
                .padding(.leading, 24)
        }
        .padding(.vertical, 4)
    }
}

struct IDFilteredView: View {
    let id: String
    let viewModel: BBSViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == id }) { post in
                PostRow(post: post, viewModel: viewModel) { _ in }
            }
            .navigationTitle("ID:\(id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
