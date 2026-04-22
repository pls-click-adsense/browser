import SwiftUI
import WebKit

@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var isFetching = false
    
    // 簡易キャッシュ (ThreadID: Posts)
    private var postCache: [String: [Post]] = [:]

    // --- エラー修正：Webデータとキャッシュのクリア ---
    func clearWebData() async {
        // メモリキャッシュを空にする
        postCache.removeAll()
        posts.removeAll()
        
        // WebViewのキャッシュやクッキーを物理的に削除
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        
        // リストを再取得
        await fetchThreadList()
    }

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
            self.threads = text.components(separatedBy: .newlines).compactMap { line in
                let parts = line.components(separatedBy: "<>")
                if parts.count < 2 { return nil }
                let datId = parts[0].replacingOccurrences(of: ".dat", with: "")
                guard let timestamp = Double(datId) else { return nil }
                let parts2 = parts[1].components(separatedBy: " (")
                let countStr = parts2.last?.replacingOccurrences(of: ")", with: "") ?? "0"
                let title = parts2.dropLast().joined(separator: " (")
                let count = Int(countStr) ?? 0
                return Thread(id: datId, title: decodeHTML(title), resCount: count, ikioi: Double(count)/max((now-timestamp)/3600,0.1), createdAt: timestamp)
            }.sorted { $0.ikioi > $1.ikioi }
        } catch { print(error) }
        isFetching = false
    }

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
            
            // 被安価の計算ロジック
            for i in 0..<newPosts.count {
                let body = newPosts[i].body
                let pattern = ">>(\\d+)"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
                    for match in matches {
                        if let range = Range(match.range(at: 1), in: body),
                           let targetNum = Int(body[range]),
                           targetNum > 0 && targetNum <= newPosts.count {
                            newPosts[targetNum - 1].addReply(from: newPosts[i].id)
                        }
                    }
                }
            }
            
            self.posts = newPosts
            self.postCache[datId] = newPosts
        } catch { print(error) }
        isFetching = false
    }

    func postReply(threadId: String, name: String, mail: String, body: String) async -> Bool {
        guard let url = URL(string: AppConfig.postURL) else { return false }
        let sjis = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        func escape(_ s: String) -> String { s.data(using: sjis)?.map { String(format: "%%%02X", $0) }.joined() ?? "" }
        let bodyStr = "bbs=liveedge&key=\(threadId)&FROM=\(escape(name))&mail=\(escape(mail))&MESSAGE=\(escape(body))&submit=\(escape("書き込む"))"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyStr.data(using: .ascii)
        req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let text = String(data: data, encoding: sjis) ?? ""
            return text.contains("書き込みました") || text.contains("正常に")
        } catch { return false }
    }

    func extractID(from str: String) -> String? { str.components(separatedBy: "ID:").last?.trimmingCharacters(in: .whitespaces) }
}
