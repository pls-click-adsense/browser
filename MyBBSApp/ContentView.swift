import SwiftUI

// MARK: - Models
struct Thread: Identifiable {
    let id: String
    let title: String
    let resCount: String
}

struct Post: Identifiable {
    let id: Int
    let name: String
    let mail: String
    let dateAndId: String
    let body: String
    
    // 安価リンクとテキストの装飾
    var attributedBody: AttributedString {
        var attrString = AttributedString(body)
        let pattern = ">>(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attrString }
        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, options: [], range: range)
        
        for match in matches.reversed() {
            guard let resRange = Range(match.range, in: attrString),
                  let numRange = Range(match.range(at: 1), in: body) else { continue }
            let resNumber = body[numRange]
            attrString[resRange].link = URL(string: "anka://\(resNumber)")
            attrString[resRange].foregroundColor = .blue
        }
        return attrString
    }
    
    // Imgurの画像URLを抽出
    var imageUrls: [URL] {
        let pattern = "https?://(?:i\\.)?imgur\\.com/([a-zA-Z0-9]+)(?:\\.[a-z]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, options: [], range: range)
        
        return matches.compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: body) else { return nil }
            let imageID = body[idRange]
            // 直接画像ファイルを参照するために .jpg を付与して i.imgur.com に統一
            return URL(string: "https://i.imgur.com/\(imageID).jpg")
        }
    }
}

struct IdentifiableID: Identifiable { let id: String }
struct ResNum: Identifiable { let id = UUID(); let num: Int }

// MARK: - ViewModel
@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var idCounts: [String: Int] = [:]
    @Published var isFetching = false
    
    let baseURL = "https://bbs.eddibb.cc/liveedge/"
    
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
                let cleanName = parts[0].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                let cleanBody = parts[3].replacingOccurrences(of: "<br>", with: "\n")
                    .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&amp;", with: "&")
                return Post(id: index + 1, name: cleanName, mail: parts[1], dateAndId: parts[2], body: cleanBody)
            }
            self.posts = newPosts
            var counts: [String: Int] = [:]
            for post in newPosts { if let id = extractID(from: post.dateAndId) { counts[id, default: 0] += 1 } }
            self.idCounts = counts
        } catch { print(error) }
        isFetching = false
    }
    
    func extractID(from str: String) -> String? {
        let pattern = "ID:([^\\s]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        if let match = regex?.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)) {
            return String(str[Range(match.range(at: 1), in: str)!])
        }
        return nil
    }
    
    func getIDStats(for post: Post) -> (current: Int, total: Int) {
        guard let id = extractID(from: post.dateAndId) else { return (0, 0) }
        return (posts.prefix(post.id).filter { extractID(from: $0.dateAndId) == id }.count, idCounts[id] ?? 0)
    }
}

// MARK: - Views
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
            .navigationTitle("liveedge")
            .refreshable { await viewModel.fetchThreadList() }
            .onAppear { if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } } }
        }
    }
}

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    @State private var selectedID: String? = nil
    @State private var targetResNumber: Int? = nil
    
    var body: some View {
        List(viewModel.posts) { post in
            PostRow(post: post, viewModel: viewModel, onIDTap: { selectedID = $0 }, onAnkaTap: { targetResNumber = $0 })
        }
        .listStyle(.plain)
        .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                    if viewModel.isFetching { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { identID in
            IDFilteredView(id: identID.id, viewModel: viewModel)
        }
        .popover(item: Binding(get: { targetResNumber.map { ResNum(num: $0) } }, set: { targetResNumber = $0?.num })) { resNum in
            if let target = viewModel.posts.first(where: { $0.id == resNum.num }) {
                ScrollView {
                    PostRow(post: target, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in })
                        .padding()
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
}

struct PostRow: View {
    let post: Post
    let viewModel: BBSViewModel
    let onIDTap: (String) -> Void
    let onAnkaTap: (Int) -> Void
    
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
                    }
                    .font(.caption2).foregroundColor(.secondary)
                }
            }
            .font(.caption)
            
            // 本文
            Text(post.attributedBody)
                .font(.body)
                .textSelection(.enabled)
                .padding(.leading, 24)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "anka", let num = Int(url.host ?? "") {
                        onAnkaTap(num)
                        return .handled
                    }
                    return .systemAction
                })
            
            // 画像サムネイル
            if !post.imageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(post.imageUrls, id: \.self) { url in
                            AsyncImage(url: url) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(8)
                            } placeholder: {
                                ProgressView().frame(width: 150, height: 150)
                            }
                        }
                    }
                    .padding(.leading, 24)
                }
            }
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
                PostRow(post: post, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in })
            }
            .navigationTitle("ID:\(id)").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

// MARK: - Encoding Help
extension Data {
    var sjisString: String? {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: self, encoding: encoding)
    }
}
