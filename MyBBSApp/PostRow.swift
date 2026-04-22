import SwiftUI

struct PostRow: View {
    let post: Post
    let viewModel: BBSViewModel
    let onIDTap: (String) -> Void
    let onAnkaTap: (Int) -> Void
    let onImageTap: (URL) -> Void
    let onRefTap: ([Int]) -> Void
    let onURLTap: (URL) -> Void // 内部ブラウザで開くためのコールバック

    var body: some View {
        let stats = viewModel.getIDStats(for: post)
        let idString = viewModel.extractID(from: post.dateAndId) ?? "???"
        
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー部分（レス番号、名前、被安価数、ID、日付）
            HStack(alignment: .top) {
                Text("\(post.id)").bold().foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(post.name).foregroundColor(.green).bold()
                        
                        // 被安価数 (x) ボタン
                        if !post.referencedBy.isEmpty {
                            Button(action: { onRefTap(post.referencedBy) }) {
                                Text("(\(post.referencedBy.count))")
                                    .font(.caption2).bold()
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Button(action: { onIDTap(idString) }) {
                            Text("ID:\(idString)").underline()
                        }.buttonStyle(.plain)
                        
                        Text("(\(stats.current)/\(stats.total))")
                            .foregroundColor(stats.total >= 5 ? .red : .secondary)
                        
                        Text(post.dateAndId.components(separatedBy: " ID:")[0])
                    }.font(.caption2).foregroundColor(.secondary)
                }
            }.font(.caption)
            
            // 本文（アンカーとURLのリンク処理）
            Text(post.attributedBody)
                .font(.body)
                .textSelection(.enabled)
                .padding(.leading, 24)
                .environment(\.openURL, OpenURLAction { url in
                    // アンカーリンク (anka://番号) の場合
                    if url.scheme == "anka", let num = Int(url.host ?? "") {
                        onAnkaTap(num)
                        return .handled
                    }
                    // 普通のURLの場合は内部ブラウザに投げる
                    onURLTap(url)
                    return .handled
                })
            
            // Imgurなどの画像プレビュー
            if !post.imageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(post.imageUrls, id: \.self) { url in
                            Button(action: { onImageTap(url) }) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 120, height: 120)
                                        .cornerRadius(8)
                                } placeholder: {
                                    ProgressView().frame(width: 120, height: 120)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.leading, 24)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
