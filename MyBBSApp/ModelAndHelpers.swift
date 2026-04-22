import SwiftUI
import WebKit

struct AppConfig {
    // 板のトップURL（末尾のスラッシュは付けておくのが無難）
    static let boardURL = "https://bbs.eddibb.cc/liveedge/"
    
    // 書き込み用CGI
    static let postURL = "https://bbs.eddibb.cc/test/bbs.cgi"
    
    // 指定のUA
    static let customUserAgent = "Monazilla/1.00 (AbeShinzo/1.0.0)"
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
    var referencedBy: [Int] = [] // 自分へのレス番号リスト
}

enum SortOption: String, CaseIterable { case ikioi = "🔥 勢い順", resCount = "📊 レス数順", new = "✨ 新着順" }
struct IdentifiableID: Identifiable { let id: String }
struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }
struct IdentifiableResList: Identifiable { let id = UUID(); let ids: [Int] } // 追加

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

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(); webView.customUserAgent = AppConfig.customUserAgent; return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { uiView.load(URLRequest(url: url)) }
}

extension Post {
    var attributedBody: AttributedString {
        let cleanBody: String = decodeHTMLEntities(body)
        var attrString = AttributedString(cleanBody)
        let range = NSRange(cleanBody.startIndex..., in: cleanBody)
        
        let ankaPattern = ">>(\\d+)"
        if let regex = try? NSRegularExpression(pattern: ankaPattern) {
            let matches = regex.matches(in: cleanBody, options: [], range: range)
            for match in matches.reversed() {
                guard let resRange = Range(match.range, in: attrString),
                      let numRange = Range(match.range(at: 1), in: cleanBody) else { continue }
                attrString[resRange].link = URL(string: "anka://\(cleanBody[numRange])")
                attrString[resRange].foregroundColor = .blue
            }
        }
        
        let urlPattern = "https?://[a-zA-Z0-9\\-\\.\\/\\?\\:\\@\\&\\=\\%\\#\\_\\!\\~\\*\\'\\(\\)\\,\\+]+"
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = regex.matches(in: cleanBody, options: [], range: range)
            for match in matches.reversed() {
                guard let resRange = Range(match.range, in: attrString),
                      let urlRange = Range(match.range, in: cleanBody),
                      let url = URL(string: String(cleanBody[urlRange])) else { continue }
                attrString[resRange].link = url
                attrString[resRange].foregroundColor = .blue
                attrString[resRange].underlineStyle = .single
            }
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
