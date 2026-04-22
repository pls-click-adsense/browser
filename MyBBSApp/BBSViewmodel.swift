import Foundation

@MainActor
class BBSViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var posts: [Post] = []
    @Published var isFetching = false
    
    func fetchThreads() async {
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "subject.txt") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = data.sjisString {
                self.threads = parseThreads(content)
            }
        } catch { print(error) }
        isFetching = false
    }
    
    func fetchPosts(datId: String) async {
        isFetching = true
        guard let url = URL(string: AppConfig.boardURL + "dat/\(datId).dat") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = data.sjisString {
                let rawPosts = parsePosts(content)
                self.posts = analyzeReferences(for: rawPosts)
            }
        } catch { print(error) }
        isFetching = false
    }
    
    private func analyzeReferences(for rawPosts: [Post]) -> [Post] {
        var updated = rawPosts
        let regex = try? NSRegularExpression(pattern: ">>(\\d+)")
        
        for post in rawPosts {
            let nsBody = post.body as NSString
            let matches = regex?.matches(in: post.body, range: NSRange(location: 0, length: nsBody.length)) ?? []
            for m in matches {
                if let r = Range(m.range(at: 1), in: post.body), let targetId = Int(post.body[r]) {
                    if let idx = updated.firstIndex(where: { $0.id == targetId }) {
                        updated[idx].referencedBy.append(post.id)
                    }
                }
            }
        }
        return updated
    }
    
    private func parseThreads(_ content: String) -> [Thread] {
        content.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "<>")
            guard parts.count >= 2, let datId = parts[0].components(separatedBy: ".").first else { return nil }
            let titleAndCount = parts[1]
            let countPattern = "\\((\\d+)\\)$"
            let regex = try? NSRegularExpression(pattern: countPattern)
            let nsString = titleAndCount as NSString
            let match = regex?.firstMatch(in: titleAndCount, range: NSRange(location: 0, length: nsString.length))
            let count = match.map { Int(nsString.substring(with: $0.range(at: 1))) ?? 0 } ?? 0
            let title = regex?.stringByReplacingMatches(in: titleAndCount, range: NSRange(location: 0, length: nsString.length), withTemplate: "").trimmingCharacters(in: .whitespaces) ?? titleAndCount
            return Thread(id: datId, title: title, resCount: count, ikioi: 0, createdAt: Double(datId) ?? 0)
        }
    }
    
    private func parsePosts(_ content: String) -> [Post] {
        content.components(separatedBy: "\n").enumerated().compactMap { (index, line) in
            let parts = line.components(separatedBy: "<>")
            guard parts.count >= 4 else { return nil }
            return Post(id: index + 1, name: parts[0], mail: parts[1], dateAndId: parts[2], body: parts[3])
        }
    }
    
    func extractID(from dateAndId: String) -> String? {
        let parts = dateAndId.components(separatedBy: " ID:")
        return parts.count > 1 ? parts[1] : nil
    }
    
    func getIDStats(for post: Post) -> (current: Int, total: Int) {
        let id = extractID(from: post.dateAndId) ?? ""
        let allWithID = posts.filter { extractID(from: $0.dateAndId) == id }
        let currentIdx = (allWithID.firstIndex(where: { $0.id == post.id }) ?? 0) + 1
        return (currentIdx, allWithID.count)
    }
    // BBSViewmodel.swift の中に追加
func postReply(threadId: String, name: String, mail: String, body: String) async -> Bool {
    guard let url = URL(string: AppConfig.postURL) else { return false }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(AppConfig.customUserAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(AppConfig.boardURL, forHTTPHeaderField: "Referer")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    
    let now = Int(Date().timeIntervalSince1970)
    let bodyString = "bbs=liveedge&key=\(threadId)&time=\(now)&FROM=\(name)&mail=\(mail)&MESSAGE=\(body)&submit=書き込む"
    
    // SJISエンコード（5ch/BBS.cgi仕様）
    let sjisEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
    request.httpBody = bodyString.data(using: sjisEnc, allowLossyConversion: true)
    
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
        return false
    }
  }
}
