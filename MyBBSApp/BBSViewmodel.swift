import SwiftUI
import WebKit

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
    
    // 絵文字などのSJIS外文字を数値文字参照（&#...;）に置換する関数
    func encodeForBBS(_ str: String) -> String {
        return str.unicodeScalars.reduce("") { result, scalar in
            if scalar.value <= 0x80 || (0xFF61...0xFF9F).contains(scalar.value) {
                // 基本文字や半角カナはそのまま（後でSJIS変換するため）
                return result + String(scalar)
            } else if String(scalar).data(using: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))) != nil {
                // SJISで表現可能な漢字などもそのまま
                return result + String(scalar)
            } else {
                // 絵文字などは数値文字参照に変換
                return result + "&#\(scalar.value);"
            }
        }
    }
    
    func sjisEnc(_ str: String) -> String {
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        // ここでencodeForBBSを通してからSJISパーセントエンコードする
        let safeStr = encodeForBBS(str)
        return safeStr.data(using: enc)?.map { String(format: "%%%02X", $0) }.joined() ?? ""
    }
    
    // FROMやMESSAGEにencodeForBBSを適用
    let params = [
        ("bbs", "liveedge"),
        ("key", threadId),
        ("FROM", name),
        ("mail", mail),
        ("MESSAGE", body),
        ("submit", "書き込む")
    ]
    
    let bodyStr = params.map { "\($0)=\(sjisEnc($1))" }.joined(separator: "&")
    
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = bodyStr.data(using: .ascii)
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.setValue("\(AppConfig.boardURL)\(threadId)", forHTTPHeaderField: "Referer")
    req.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, res) = try await URLSession.shared.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        
        if status == 200 {
            await fetchPosts(datId: threadId)
            return (true, "")
        }
        
        let text = data.sjisString ?? "Unknown Error"
        return (false, "Status: \(status)\n\(text)")
    } catch {
        return (false, error.localizedDescription)
    }
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
