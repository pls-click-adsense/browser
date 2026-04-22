import SwiftUI
import WebKit

struct AppConfig {
    static let customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
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

struct Post: Identifiable {
    let id: Int
    let name: String
    let mail: String
    let dateAndId: String
    let body: String
}

enum SortOption: String, CaseIterable { case ikioi = "🔥 勢い順", resCount = "📊 レス数順", new = "✨ 新着順" }
struct IdentifiableID: Identifiable { let id: String }
struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }

func decodeHTMLEntities(_ text: String) -> String {
    var decoded = text
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
    let pattern = "&#(\\d+);"
    let regex = try? NSRegularExpression(pattern: pattern)
    let matches = regex?.matches(in: decoded, options: [], range: NSRange(decoded.startIndex..., in: decoded)) ?? []
    for match in matches.reversed() {
        if let codeRange = Range(match.range(at: 1), in: decoded),
           let codePoint = UInt32(decoded[codeRange]),
           let scalar = UnicodeScalar(codePoint) {
            decoded.replaceSubrange(Range(match.range, in: decoded)!, with: String(scalar))
        }
    }
    return decoded
}

extension Data {
    var sjisString: String? {
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return String(data: self, encoding: enc)
    }
}

// 部品たち
struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(); webView.customUserAgent = AppConfig.customUserAgent; return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { uiView.load(URLRequest(url: url)) }
}

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
            HStack(alignment: .top) {
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
            Text(post.attributedBody).font(.body).textSelection(.enabled).padding(.leading, 24)
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
        }
    }
}

// Postの拡張
extension Post {
    var attributedBody: AttributedString {
        let cleanBody = decodeHTMLEntities(body)
        var attrString = AttributedString(cleanBody)
        
        // --- 1. アンカー (>>1) の処理 ---
        let ankaPattern = ">>(\\d+)"
        if let regex = try? NSRegularExpression(pattern: ankaPattern) {
            let matches = regex.matches(in: cleanBody, options: [], range: NSRange(cleanBody.startIndex..., in: cleanBody))
            for match in matches.reversed() {
                guard let resRange = Range(match.range, in: attrString),
                      let numRange = Range(match.range(at: 1), in: cleanBody) else { continue }
                attrString[resRange].link = URL(string: "anka://\(cleanBody[numRange])")
                attrString[resRange].foregroundColor = .blue
            }
        }
        
        // --- 2. 一般URL (http/https) の処理 ---
        let urlPattern = "https?://[a-zA-Z0-9\\-\\.\\/\\?\\:\\@\\&\\=\\%\\#\\_\\!\\~\\*\\'\\(\\)\\,\\+]+"
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = regex.matches(in: cleanBody, options: [], range: NSRange(cleanBody.startIndex..., in: cleanBody))
            for match in matches.reversed() {
                guard let resRange = Range(match.range, in: attrString),
                      let urlRange = Range(match.range, in: cleanBody),
                      let url = URL(string: String(cleanBody[urlRange])) else { continue }
                // Imgurなどの画像URL以外をリンク化したい場合はここでフィルタも可能だが、
                // 基本全部リンクにしておいた方が便利。
                attrString[resRange].link = url
                attrString[resRange].foregroundColor = .blue
                attrString[resRange].underlineStyle = .single
            }
        }
        
        return attrString
    }
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
