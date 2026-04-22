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

func decodeHTML(_ text: String) -> String {
    var decoded = text
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "<br>", with: "\n")

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
    return decoded
}

struct Post: Identifiable {
    let id: Int
    let name: String
    let mail: String
    let dateAndId: String
    let body: String
    var repliedBy: [Int] = [] // 被安価（このレスに向けられたレス番号）
    
    var attributedBody: AttributedString {
        let cleanBody = decodeHTML(body)
        var attrString = AttributedString(cleanBody)
        let urlPattern = #"(https?://[^\s<>]+)"#
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
            let urlMatches = urlRegex.matches(in: cleanBody, range: NSRange(cleanBody.startIndex..., in: cleanBody))
            for match in urlMatches.reversed() {
                if let range = Range(match.range, in: attrString),
                   let urlRange = Range(match.range, in: cleanBody),
                   let url = URL(string: String(cleanBody[urlRange])) {
                    attrString[range].link = url
                    attrString[range].foregroundColor = .blue
                }
            }
        }
        let ankaPattern = ">>(\\d+)"
        if let ankaRegex = try? NSRegularExpression(pattern: ankaPattern) {
            let ankaMatches = ankaRegex.matches(in: cleanBody, range: NSRange(cleanBody.startIndex..., in: cleanBody))
            for match in ankaMatches.reversed() {
                if let range = Range(match.range, in: attrString),
                   let numRange = Range(match.range(at: 1), in: cleanBody) {
                    attrString[range].link = URL(string: "anka://\(cleanBody[numRange])")
                    attrString[range].foregroundColor = .blue
                }
            }
        }
        return attrString
    }

    var imageUrls: [URL] {
        let pattern = #"(https?://(?:pbs\.twimg\.com/media/[a-zA-Z0-9_-]+|i\.imgur\.com/[a-zA-Z0-9]+)(?:\.[a-z]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: body, options: [], range: NSRange(body.startIndex..., in: body))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: body) else { return nil }
            return URL(string: String(body[range]))
        }
    }
}

struct PostRow: View {
    let post: Post
    let viewModel: BBSViewModel
    let onIDTap: (String) -> Void
    let onAnkaTap: (Int) -> Void
    let onImageTap: (URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        let idString = viewModel.extractID(from: post.dateAndId) ?? "???"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(post.id)").bold().foregroundColor(.secondary)
                Text(decodeHTML(post.name)).foregroundColor(.green).bold()
                Button(action: { onIDTap(idString) }) { Text("ID:\(idString)").underline() }.buttonStyle(.plain)
                Text(post.dateAndId.components(separatedBy: " ID:")[0])
            }.font(.caption2).foregroundColor(.secondary)
            
            Text(post.attributedBody)
                .font(.body).textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "anka", let num = Int(url.host ?? "") { onAnkaTap(num); return .handled }
                    onURLTap(url)
                    return .handled
                })

            if !post.imageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(post.imageUrls, id: \.self) { url in
                            AsyncImage(url: url) { i in 
                                i.resizable().aspectRatio(contentMode: .fill).frame(width: 120, height: 120).cornerRadius(8)
                            } placeholder: { ProgressView() }
                            .onTapGesture { onImageTap(url) }
                        }
                    }
                }
            }
            
            // 被安価の表示
            if !post.repliedBy.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                    ForEach(post.repliedBy, id: \.self) { num in
                        Button(action: { onAnkaTap(num) }) {
                            Text(">>\(num)").font(.caption2).bold().padding(4).background(Color.gray.opacity(0.1)).cornerRadius(4)
                        }.buttonStyle(.plain)
                    }
                }.foregroundColor(.blue).padding(.top, 2)
            }
        }
    }
}
