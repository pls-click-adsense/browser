import SwiftUI

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    
    @State private var selectedID: String? = nil
    @State private var targetAnka: Int? = nil
    @State private var showingRefs: [Int]? = nil
    @State private var zoomImageURL: URL? = nil
    @State private var webURL: URL? = nil

    var body: some View {
        ScrollViewReader { proxy in
            List(viewModel.posts) { post in
                PostRow(
                    post: post,
                    viewModel: viewModel,
                    onIDTap: { selectedID = $0 },
                    onAnkaTap: { targetAnka = $0 },
                    onImageTap: { zoomImageURL = $0 },
                    onRefTap: { showingRefs = $0 }
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
        // ID検索
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            NavigationStack {
                List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == idObj.id }) { p in
                    simpleRow(p)
                }.navigationTitle("ID:\(idObj.id)")
            }
        }
        // 安価単体表示
        .sheet(item: Binding(get: { targetAnka.map { IdentifiableID(id: String($0)) } }, set: { _ in targetAnka = nil })) { obj in
            if let p = viewModel.posts.first(where: { String($0.id) == obj.id }) {
                NavigationStack { List { simpleRow(p) }.listStyle(.plain).navigationTitle(">>\(obj.id)") }
            }
        }
        // 被安価リスト表示
        .sheet(item: Binding(get: { showingRefs.map { IdentifiableResList(ids: $0) } }, set: { showingRefs = $0?.ids })) { refObj in
            NavigationStack {
                List(viewModel.posts.filter { refObj.ids.contains($0.id) }) { p in
                    simpleRow(p)
                }.navigationTitle("このレスへの返信")
            }
        }
    }
    
    func simpleRow(_ p: Post) -> some View {
        PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { targetAnka = $0 }, onImageTap: { zoomImageURL = $0 }, onRefTap: { showingRefs = $0 })
    }
}
