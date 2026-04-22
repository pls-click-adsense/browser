import SwiftUI

struct ThreadDetailView: View {
    @ObservedObject var viewModel: BBSViewModel
    let thread: Thread
    @State private var selectedID: String? = nil
    @State private var targetRes: Post? = nil
    @State private var zoomImageURL: URL? = nil
    @State private var isShowingPostView = false
    
    var body: some View {
        List(viewModel.posts) { post in
            PostRow(post: post, viewModel: viewModel, 
                    onIDTap: { selectedID = $0 }, 
                    onAnkaTap: { num in targetRes = viewModel.posts.first { $0.id == num } },
                    onImageTap: { zoomImageURL = $0 })
        }
        .listStyle(.plain)
        .navigationTitle(thread.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await viewModel.fetchPosts(datId: thread.id) } }) {
                    if viewModel.isFetching { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { isShowingPostView = true }) {
                Image(systemName: "pencil.circle.fill").resizable().frame(width: 56, height: 56)
                    .foregroundColor(.blue).background(Color.white.clipShape(Circle())).shadow(radius: 4)
            }.padding(24)
        }
        .sheet(item: Binding(get: { selectedID.map { IdentifiableID(id: $0) } }, set: { selectedID = $0?.id })) { idObj in
            NavigationStack {
                List(viewModel.posts.filter { viewModel.extractID(from: $0.dateAndId) == idObj.id }) { p in
                    PostRow(post: p, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { _ in })
                }
                .navigationTitle("ID:\(idObj.id)").toolbar { Button("閉じる") { selectedID = nil } }
            }
        }
        .sheet(item: $targetRes) { post in
            VStack {
                Capsule().frame(width: 40, height: 6).foregroundColor(.secondary).padding(.top, 8)
                PostRow(post: post, viewModel: viewModel, onIDTap: { _ in }, onAnkaTap: { _ in }, onImageTap: { zoomImageURL = $0 }).padding()
                Spacer()
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingPostView) { PostView(viewModel: viewModel, threadId: thread.id) }
        .fullScreenCover(item: Binding(get: { zoomImageURL.map { IdentifiableURL(url: $0) } }, set: { zoomImageURL = $0?.url })) { urlObj in
            ZStack { Color.black.ignoresSafeArea(); AsyncImage(url: urlObj.url) { i in i.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() } }
            .onTapGesture { zoomImageURL = nil }
        }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
}
