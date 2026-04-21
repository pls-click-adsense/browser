import SwiftUI

// MARK: - 1. データ構造 (Models)
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

// MARK: - 2. Shift-JIS変換用の拡張 (Encoding)
extension Data {
    var sjisString: String? {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: self, encoding: encoding)
    }
}

// MARK: - 3. 通信・解析ロジック (Logic)
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    
    let baseURL = "https://bbs.eddibb.cc/liveedge/"
    
    // スレ一覧 (subject.txt) を取得
    func fetchThreadList() async {
        guard let url = URL(string: baseURL + "subject.txt") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rawText = data.sjisString else { return }
            
            let lines = rawText.components(separatedBy: .newlines)
            DispatchQueue.main.async {
                self.threads = lines.compactMap { line in
                    let parts = line.components(separatedBy: "<>")
                    guard parts.count >= 2 else { return nil }
                    let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                    
                    // タイトル(レス数) を分離
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
            }
        } catch {
            print("Fetch error: \(error)")
        }
    }
    
    // スレ内レス (dat) を取得
    func fetchPosts(datId: String) async {
        guard let url = URL(string: baseURL + "dat/\(datId).dat") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rawText = data.sjisString else { return }
            
            let lines = rawText.components(separatedBy: .newlines)
            DispatchQueue.main.async {
                self.posts = lines.enumerated().compactMap { index, line in
                    let parts = line.components(separatedBy: "<>")
                    guard parts.count >= 4 else { return nil }
                    
                    // 本文のHTMLタグを簡易置換
                    let cleanBody = parts[3]
                        .replacingOccurrences(of: "<br>", with: "\n")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&lt;", with: "<")
                    
                    return Post(
                        id: index + 1,
                        name: parts[0],
                        mail: parts[1],
                        dateAndId: parts[2],
                        body: cleanBody
                    )
                }
            }
        } catch {
            print("Fetch error: \(error)")
        }
    }
}

// MARK: - 4. UI画面 (Views)

// メイン画面（スレ一覧）
struct ContentView: View {
    @StateObject var viewModel = BBSViewModel()
    
    var body: some View {
        NavigationStack {
            List(viewModel.threads) { thread in
                NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: thread)) {
                    HStack {
                        Text(thread.title)
                            .lineLimit(1)
                        Spacer()
                        Text(thread.resCount)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("スレ一覧")
            .refreshable {
                await viewModel.fetchThreadList()
            }
            .onAppear {
                Task { await viewModel.fetchThreadList() }
            }
        }
    }
}

// スレ内画面（レス一覧）
struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    
    var body: some View {
        List(viewModel.posts) { post in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(post.id)")
                    Text(post.name).foregroundColor(.green)
                    Text(post.dateAndId).font(.caption2).foregroundColor(.secondary)
                }
                .font(.caption)
                
                Text(post.body)
                    .font(.body)
                    .textSelection(.enabled) // 本文をコピーできるように
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await viewModel.fetchPosts(datId: thread.id) }
        }
        .onDisappear {
            viewModel.posts = [] // 戻る時にクリア
        }
    }
}
