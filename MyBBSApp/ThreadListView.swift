import SwiftUI

struct ThreadListView: View {
    @StateObject var viewModel = BBSViewModel()
    @State private var searchText = ""
    @State private var sortOption: SortOption = .ikioi
    
    var filteredThreads: [Thread] {
        let list = searchText.isEmpty ? viewModel.threads : viewModel.threads.filter { $0.title.contains(searchText) }
        switch sortOption {
        case .ikioi: return list.sorted { $0.ikioi > $1.ikioi }
        case .resCount: return list.sorted { $0.resCount > $1.resCount }
        case .new: return list.sorted { $0.createdAt > $1.createdAt }
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredThreads) { thread in
                NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: thread)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(thread.title).font(.headline).lineLimit(2)
                        HStack {
                            Text("\(thread.resCount) res").foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f", thread.ikioi)).foregroundColor(.orange).bold()
                        }.font(.caption)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("エッジ板")
            .searchable(text: $searchText, prompt: "スレタイ検索")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("ソート", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .onAppear { Task { await viewModel.fetchThreads() } }
        }
    }
}
