import SwiftUI
import WebKit

@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var isFetching = false
    @Published var isLoadingMore = false // 追加読み込み中フラグ
    
    @Published var sortOption: SortOption = .ikioi {
        didSet { applySort() }
    }
    
    private var postCache: [String: [Post]] = [:]

    // --- Webデータ削除（ワンクッション後に実行される） ---
    func clearWebData() async {
        postCache.removeAll()
        posts.removeAll()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        await fetchThreadList()
    }

    // --- スレッド一覧取得 ---
    func fetchThreadList() async {
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "subject.txt") else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let sjis = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
            guard let text = String(data: data, encoding: sjis) else { return }
            
            let now = Date().timeIntervalSince1970
            let newThreads = text.components(separatedBy: .newlines).compactMap { line -> Thread? in
                let parts = line.components(separatedBy: "<>")
                if parts.count < 2 { return nil }
                let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                guard let timestamp = Double(datId) else { return nil }
                let parts2 = parts[1].components(separatedBy: " (")
                let countStr = parts2.last?.replacingOccurrences(of: ")", with: "") ?? "0"
                let title = parts2.dropLast().joined(separator: " (")
                let count = Int(countStr) ?? 0
                return Thread(id: datId, title: decodeHTML(title), resCount: count, ikioi: Double(count)/max((now-timestamp)/3600, 0.1), createdAt: timestamp)
            }
            self.threads = newThreads
            applySort()
        } catch { print(error) }
        isFetching = false
    }

    // --- 上に引っ張って追加読み込み（の演出とロジック） ---
    func loadMoreThreadsIfNeeded(currentThread: Thread) async {
        guard threads.last?.id == currentThread.id, !isLoadingMore else { return }
        
        isLoadingMore = true
        // 板の仕様上、subject.txtは一括取得だけど、演出として少し待機
        try? await Task.sleep(nanoseconds: 500_000_000) 
        // 実際に追加データがあるAPIならここで append する
        isLoadingMore = false
    }

    private func applySort() {
        switch sortOption {
        case .ikioi: threads.sort { $0.ikioi > $1.ikioi }
        case .new: threads.sort { $0.createdAt > $1.createdAt }
        case .resCount: threads.sort { $0.resCount > $1.resCount }
        }
    }

    // レス取得
    func fetchPosts(datId: String, useCache: Bool = false) async {
        if useCache, let cached = postCache[datId] {
            self.posts = cached
            return
        }
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "dat/\(datId).dat") else { return }
        var req = URLRequest(url: url)
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let sjis = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
            guard let text = String(data: data, encoding: sjis) else { return }
            var newPosts = text.components(separatedBy: .newlines).enumerated().compactMap { i, line -> Post? in
                let p = line.components(separatedBy: "<>")
                if p.count < 4 { return nil }
                return Post(id: i + 1, name: p[0], mail: p[1], dateAndId: p[2], body: p[3])
            }
            self.posts = newPosts
            self.postCache[datId] = newPosts
        } catch { print(error) }
        isFetching = false
    }
}
