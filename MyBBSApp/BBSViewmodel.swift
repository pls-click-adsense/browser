import SwiftUI
import WebKit

@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var isFetching = false
    @Published var sortOption: SortOption = .ikioi { didSet { applySort() } }
    
    private var rawThreads: [Thread] = []
    
    func fetchThreadList() async {
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "subject.txt") else { return }
        var req = URLRequest(url: url)
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let sjis = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
            guard let text = String(data: data, encoding: sjis) else { return }
            
            let now = Date().timeIntervalSince1970
            self.rawThreads = text.components(separatedBy: .newlines).compactMap { line in
                let parts = line.components(separatedBy: "<>")
                if parts.count < 2 { return nil }
                let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                guard let timestamp = Double(datId) else { return nil }
                let parts2 = parts[1].components(separatedBy: " (")
                let countStr = parts2.last?.replacingOccurrences(of: ")", with: "") ?? "0"
                let title = parts2.dropLast().joined(separator: " (")
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
        var req = URLRequest(url: url)
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let sjis = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
            guard let text = String(data: data, encoding: sjis) else { return }
            self.posts = text.components(separatedBy: .newlines).enumerated().compactMap { i, line in
                let p = line.components(separatedBy: "<>")
                if p.count < 4 { return nil }
                return Post(id: i + 1, name: p[0], mail: p[1], dateAndId: p[2], body: p[3].replacingOccurrences(of: "<br>", with: "\n"))
            }
        } catch { print(error) }
        isFetching = false
    }

    func postReply(threadId: String, name: String, mail: String, body: String) async -> Bool {
        guard let url = URL(string: AppConfig.postURL) else { return false }
        let sjis = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        func escape(_ s: String) -> String {
            s.data(using: sjis)?.map { String(format: "%%%02X", $0) }.joined() ?? ""
        }
        let bodyStr = "bbs=liveedge&key=\(threadId)&FROM=\(escape(name))&mail=\(escape(mail))&MESSAGE=\(escape(body))&submit=\(escape("書き込む"))"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyStr.data(using: .ascii)
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let text = String(data: data, encoding: sjis) ?? ""
            if text.contains("書き込みました") || text.contains("正常に") {
                await fetchPosts(datId: threadId)
                return true
            }
        } catch { print(error) }
        return false
    }

    func extractID(from str: String) -> String? {
        str.components(separatedBy: "ID:").last?.trimmingCharacters(in: .whitespaces)
    }

    func getIDStats(for p: Post) -> (current: Int, total: Int) {
        guard let id = extractID(from: p.dateAndId) else { return (1, 1) }
        let allIDs = posts.compactMap { extractID(from: $0.dateAndId) }
        let total = allIDs.filter { $0 == id }.count
        let current = allIDs.prefix(p.id).filter { $0 == id }.count
        return (current, total)
    }

    func clearWebData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0))
    }
}
