import SwiftUI

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    @State private var selectedID: String? = nil
    @State private var targetAnka: Int? = nil
    @State private var zoomImageURL: URL? = nil
    @State private var isShowingPostView = false
    @State private var webURL: IdentifiableURL? = nil

    var body: some View {
        ScrollViewReader { proxy in
            List(viewModel.posts) { post in
                PostRow(post: post, viewModel: viewModel,
                        onIDTap: { selectedID = $0 },
                        onAnkaTap: { targetAnka = $0 },
                        onImageTap: { zoomImageURL = $0 },
                        onURLTap: { webURL = (IdentifiableURL(url: $0)) })
                .id(post.id)
            }
            .listStyle(.plain)
            .refreshable { await viewModel.fetchPosts(datId: thread.id) } // 下に引っ張ってリロード
            .safeAreaInset(edge: .bottom) { // 下部固定メニュー
                HStack(spacing: 20) {
                    Button(action: { withAnimation { proxy.scrollTo(1, anchor: .top) } }) {
                        Image(systemName: "chevron.up.circle.fill")
                    }
                    Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                    }
                    Button(action: { isShowingPostView = true }) {
                        Image(systemName: "pencil.circle.fill").font(.largeTitle)
                    }
                    Button(action: {
                        if let last = viewModel.posts.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }) {
                        Image(systemName: "chevron.down.circle.fill")
                    }
                }
                .font(.title2).padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(.ultraThinMaterial) // 透ける素材でカッコよく
            }
            .navigationTitle(thread.title)
            .onAppear { Task { await viewModel.fetchPosts(datId: thread.id, useCache: true) } }
        }
        // ... (以下、sheetやfullScreenCoverのコードは前回と同じ)
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            NavigationStack {
                List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == idObj.id }) { p in
                    PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { targetAnka = $0 }, onImageTap: { zoomImageURL = $0 }, onURLTap: { webURL = IdentifiableURL(url: $0) })
                }.navigationTitle("ID:\(idObj.id)")
            }
        }
        .sheet(item: Binding(get: { targetAnka.map { IdentifiableID(id: String($0)) } }, set: { _ in targetAnka = nil })) { obj in
            if let p = viewModel.posts.first(where: { String($0.id) == obj.id }) {
                PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { zoomImageURL = $0 }, onURLTap: { webURL = IdentifiableURL(url: $0) }).padding()
            }
        }
        .sheet(isPresented: $isShowingPostView) { PostView(viewModel: viewModel, threadId: thread.id) }
        .sheet(item: $webURL) { item in NavigationStack { WebView(url: item.url).toolbar { Button("閉じる") { webURL = nil } } } }
        .fullScreenCover(item: Binding(get: { zoomImageURL.map { IdentifiableURL(url: $0) } }, set: { zoomImageURL = $0?.url })) { item in
            ZStack { Color.black.ignoresSafeArea(); AsyncImage(url: item.url) { i in i.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() } }
            .onTapGesture { zoomImageURL = nil }
        }
    }
}
