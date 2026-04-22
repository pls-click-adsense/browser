import SwiftUI

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    
    @State private var selectedID: String? = nil
    @State private var targetAnka: Int? = nil
    @State private var showingRefs: [Int]? = nil
    @State private var zoomImageURL: URL? = nil
    @State private var webURL: IdentifiableURL? = nil // リンク用
    @State private var isShowingPostView = false // 書き込み用

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                List(viewModel.posts) { post in
                    PostRow(
                        post: post,
                        viewModel: viewModel,
                        onIDTap: { selectedID = $0 },
                        onAnkaTap: { targetAnka = $0 },
                        onImageTap: { zoomImageURL = $0 },
                        onRefTap: { showingRefs = $0 },
                        onURLTap: { url in webURL = IdentifiableURL(url: url) } // URLタップ追加
                    ).id(post.id)
                }
                .listStyle(.plain)
                .navigationTitle(thread.title)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: { withAnimation { proxy.scrollTo(1, anchor: .top) } }) { Image(systemName: "chevron.up.circle") }
                        Button(action: { if let last = viewModel.posts.last?.id { withAnimation { proxy.scrollTo(last, anchor: .bottom) } } }) { Image(systemName: "chevron.down.circle") }
                        Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            
            // 書き込みボタン（右下）
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { isShowingPostView = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .resizable()
                            .frame(width: 56, height: 56)
                            .foregroundColor(.blue)
                            .background(Color.white.clipShape(Circle()))
                            .shadow(radius: 4)
                    }
                    .padding(24)
                }
            }
        }
        // 書き込み画面
        .sheet(isPresented: $isShowingPostView) {
            PostView(viewModel: viewModel, threadId: thread.id)
        }
        // ID検索・安価・被安価のポップアップ（既存どおり）
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            NavigationStack {
                List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == idObj.id }) { p in
                    simpleRow(p)
                }.navigationTitle("ID:\(idObj.id)")
            }
        }
        .sheet(item: Binding(get: { targetAnka.map { IdentifiableID(id: String($0)) } }, set: { _ in targetAnka = nil })) { obj in
            if let p = viewModel.posts.first(where: { String($0.id) == obj.id }) {
                NavigationStack { List { simpleRow(p) }.listStyle(.plain).navigationTitle(">>\(obj.id)") }
            }
        }
        .sheet(item: Binding(get: { showingRefs.map { IdentifiableResList(ids: $0) } }, set: { showingRefs = $0?.ids })) { refObj in
            NavigationStack {
                List(viewModel.posts.filter { refObj.ids.contains($0.id) }) { p in
                    simpleRow(p)
                }.navigationTitle("このレスへの返信")
            }
        }
        // 内部ブラウザ（リンク用）
        .sheet(item: $webURL) { item in
            NavigationStack {
                WebView(url: item.url)
                    .toolbar { Button("閉じる") { webURL = nil } }
            }
        }
    }
    
    func simpleRow(_ p: Post) -> some View {
        PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { targetAnka = $0 }, onImageTap: { zoomImageURL = $0 }, onRefTap: { showingRefs = $0 }, onURLTap: { url in webURL = IdentifiableURL(url: url) })
    }
}
