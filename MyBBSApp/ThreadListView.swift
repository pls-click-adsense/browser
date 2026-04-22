import SwiftUI

struct ThreadListView: View {
    @StateObject var viewModel = BBSViewModel()
    @State private var webURL: IdentifiableURL? = nil
    
    var body: some View {
        NavigationStack {
            List(viewModel.threads) { t in
                NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: t)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.title).font(.subheadline).bold().lineLimit(2)
                        HStack {
                            Text("\(t.resCount) res").foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f", t.ikioi)).foregroundColor(.orange).bold()
                        }.font(.caption2)
                    }
                }
            }
            .navigationTitle("エッジ板")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button(action: { webURL = IdentifiableURL(url: URL(string: AppConfig.boardURL)!) }) {
                            Image(systemName: "safari")
                        }
                        Button(action: { Task { await viewModel.clearWebData() } }) {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("ソート", selection: $viewModel.sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .sheet(item: $webURL) { item in
                NavigationStack {
                    WebView(url: item.url)
                        .toolbar { Button("閉じる") { webURL = nil } }
                }
            }
            .refreshable { await viewModel.fetchThreadList() }
            .onAppear { if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } } }
        }
    }
}
