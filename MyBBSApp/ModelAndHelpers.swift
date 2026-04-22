import SwiftUI
import WebKit

struct AppConfig {
    static let customUserAgent = "AbeShinzo/1.0.0"
    static let boardURL = "https://bbs.eddibb.cc/liveedge/"
    static let postURL = "https://bbs.eddibb.cc/test/bbs.cgi"
}

struct Thread: Identifiable {
    let id: String
    let title: String
    let resCount: Int
    let ikioi: Double
    let createdAt: Double
}

// HTML実体参照・絵文字をデコードする関数
func decodeHTML(_ text: String) -> String {
    var decoded = text
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "<br>", with: "\n")

    // 10進数実体参照 (&#12345;) の処理
    let decimalPattern = "&#(\\d+);"
    if let regex = try? NSRegularExpression(pattern: decimalPattern) {
        let matches = regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded))
        for match in matches.reversed() {
            if let range = Range(match.range, in: decoded),
               let codeRange = Range(match.range(at: 1), in: decoded),
               let codePoint = UInt32(decoded[codeRange]),
               let scalar = UnicodeScalar(codePoint) {
                decoded.replaceSubrange(range, with: String(scalar))
            }
        }
    }
    
    // 16進数実体参照 (&#x...;) の処理
    let hexPattern = "&#x([0-9a-fA-F]+);"
    if let hexRegex = try? NSRegularExpression(pattern: hexPattern) {
        let hexMatches = hexRegex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded))
        for match in hexMatches.reversed() {
            if let range = Range(match.range, in: decoded),
               let codeRange = Range(match.range(at: 1), in: decoded),
               let codePoint = UInt32(decoded[codeRange], radix: 16),
               let scalar = UnicodeScalar(codePoint) {
                decoded.replaceSubrange(range, with: String(scalar))
            }
        }
    }
    return decoded
}

struct Post: Identifiable {
    let id: Int
    let name: String
    let mail: String
    let dateAndId: String
    let body: String
    
    var attributedBody: AttributedString {
        let cleanBody = decodeHTML(body)
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

enum SortOption: String, CaseIterable { 
    case ikioi = "🔥 勢い", resCount = "📊 レス数", new = "✨ 新着" 
}

struct IdentifiableID: Identifiable { let id: String }
struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.customUserAgent = AppConfig.customUserAgent
        return v
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { uiView.load(URLRequest(url: url)) }
}

struct PostRow: View {
    let post: Post
    let viewModel: BBSViewModel
    let onIDTap: (String) -> Void
    let onAnkaTap: (Int) -> Void
    let onImageTap: (URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        let stats = viewModel.getIDStats(for: post)
        let idString = viewModel.extractID(from: post.dateAndId) ?? "???"
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(post.id)").bold().foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(decodeHTML(post.name)).foregroundColor(.green).bold()
                    HStack {
                        Button(action: { onIDTap(idString) }) { Text("ID:\(idString)").underline() }.buttonStyle(.plain)
                        Text("(\(stats.current)/\(stats.total))").foregroundColor(stats.total >= 5 ? .red : .secondary)
                        Text(post.dateAndId.components(separatedBy: " ID:")[0])
                    }.font(.caption2).foregroundColor(.secondary)
                }
            }.font(.caption)
            
            Text(post.attributedBody)
                .font(.body)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "anka", let num = Int(url.host ?? "") { onAnkaTap(num); return .handled }
                    onURLTap(url)
                    return .handled
                })
            
            if !post.imageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(post.imageUrls, id: \.self) { url in
                            Button(action: { onImageTap(url) }) {
                                AsyncImage(url: url) { i in i.resizable().aspectRatio(contentMode: .fill).frame(width: 100, height: 100).cornerRadius(8) } placeholder: { ProgressView().frame(width: 100, height: 100) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
