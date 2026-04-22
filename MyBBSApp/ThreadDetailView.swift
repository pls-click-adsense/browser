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
        ZStack {
            List(viewModel.posts) { post in
                PostRow(post: post, viewModel: viewModel,
                        onIDTap: { selectedID = $0 },
                        onAnkaTap: { targetAnka = $0 },
                        onImageTap: { zoomImageURL = $0 },
                        onURLTap: { webURL = IdentifiableURL(url: $0) })
            }
            .listStyle(.plain)
            .navigationTitle(thread.title)
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { isShowingPostView = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .resizable().frame(width: 56, height: 56)
                            .foregroundColor(.blue).background(Color.white.clipShape(Circle())).shadow(radius: 4)
                    }.padding(24)
                }
            }
        }
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
        .sheet(item: $webURL) { item in WebView(url: item.url) }
        .onAppear { Task { await viewModel.fetchPosts(datId: thread.id) } }
    }
}
