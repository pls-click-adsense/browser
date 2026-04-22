import SwiftUI

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    
    @State private var isTreeMode = false
    @State private var selectedID: String? = nil
    @State private var targetRes: Post? = nil
    @State private var zoomImageURL: URL? = nil
    @State private var isShowingPostView = false
    
    // 内蔵ブラウザ表示用
    @State private var webURL: URL? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if isTreeMode {
                    // ツリー構造表示
                    List(viewModel.buildTree(from: viewModel.posts), children: \.children) { post in
                        postRowContent(post: post)
                    }
                    .listStyle(.plain)
                } else {
                    // 通常の一覧表示
                    List(viewModel.posts) { post in
                        postRowContent(post: post)
                            .id(post.id)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 表示モード切り替え
                    Button(action: { isTreeMode.toggle() }) {
                        Image(systemName: isTreeMode ? "list.bullet.indent" : "list.bullet")
                    }
                    
                    // ジャンプボタン (通常モードのみ)
                    if !isTreeMode {
                        Button(action: { withAnimation { proxy.scrollTo(1, anchor: .top) } }) {
                            Image(systemName: "chevron.up.circle")
                        }
                        Button(action: {
                            if let lastId = viewModel.posts.last?.id {
                                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                            }
                        }) {
                            Image(systemName: "chevron.down.circle")
                        }
                    }
                    
                    // 更新
                    Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                        if viewModel.isFetching { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { isShowingPostView = true }) {
                Image(systemName: "pencil.circle.fill").resizable().frame(width: 56, height: 56)
                    .foregroundColor(.blue).background(Color.white.clipShape(Circle())).shadow(radius: 4)
            }.padding(24)
        }
        // ID検索結果表示
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            NavigationStack {
                List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == idObj.id }) { p in
                    postRowContent(post: p)
                }
                .navigationTitle("ID:\(idObj.id)").toolbar { Button("閉じる") { selectedID = nil } }
            }
        }
        // アンカーポップアップ
        .sheet(item: $targetRes) { post in
            VStack {
                Capsule().frame(width: 40, height: 6).foregroundColor(.secondary).padding(.top, 8)
                postRowContent(post: post).padding()
                Spacer()
            }.presentationDetents([.medium])
        }
        // 内蔵ブラウザ表示
        .sheet(item: Binding(get: { webURL.map { IdentifiableURL(url: $0) } }, set: { webURL = $0?.url })) { urlObj in
            NavigationStack {
                WebView(url: urlObj.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("リンク先")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { Button("閉じる") { webURL = nil } }
                        ToolbarItem(placement: .navigationBarTrailing) { ShareLink(item: urlObj.url) }
                    }
            }
        }
        // 書き込み画面
        .sheet(isPresented: $isShowingPostView) { PostView(viewModel: viewModel, threadId: thread.id) }
        // 画像フルスクリーン
        .fullScreenCover(item: Binding(get: { zoomImageURL.map { IdentifiableURL(url: $0) } }, set: { zoomImageURL = $0?.url })) { urlObj in
            ZStack { Color.black.ignoresSafeArea(); AsyncImage(url: urlObj.url) { i in i.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() } }
            .onTapGesture { zoomImageURL = nil }
        }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
    
    // 共通のPostRow呼び出し（リンクハンドリング含む）
    @ViewBuilder
    func postRowContent(post: Post) -> some View {
        PostRow(post: post, viewModel: viewModel, 
                onIDTap: { selectedID = $0 }, 
                onAnkaTap: { num in targetRes = viewModel.posts.first { $0.id == num } },
                onImageTap: { zoomImageURL = $0 })
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "anka" {
                if let numStr = url.host, let num = Int(numStr) {
                    targetRes = viewModel.posts.first { $0.id == num }
                }
                return .handled
            } else if url.scheme == "http" || url.scheme == "https" {
                webURL = url
                return .handled
            }
            return .systemAction
        })
    }
}
