import SwiftUI

struct ThreadListView: View {
    @StateObject var viewModel = BBSViewModel()
    @State private var showClearConfirm = false
    
    var body: some View {
        NavigationView {
            ZStack {
                mainList
                
                if viewModel.isFetching && viewModel.threads.isEmpty {
                    ProgressView("読み込み中...")
                }
            }
            .navigationTitle("ニュース速報(VIP)")
            .toolbar {
                toolbarItems
            }
        }
        .confirmationDialog("データの削除", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("キャッシュとクッキーを消去", role: .destructive) {
                Task { await viewModel.clearWebData() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("すべての閲覧履歴とクッキーが削除されます。")
        }
        .onAppear {
            if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } }
        }
    }

    // List部分を切り出してコンパイル負荷を軽減
    private var mainList: some View {
        List {
            ForEach(viewModel.threads) { thread in
                NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: thread)) {
                    ThreadRow(thread: thread)
                }
                .onAppear {
                    Task { await viewModel.loadMoreThreadsIfNeeded(currentThread: thread) }
                }
            }
            
            if viewModel.isLoadingMore {
                loadingIndicator
            }
        }
        .refreshable { await viewModel.fetchThreadList() }
    }

    private var loadingIndicator: some View {
        HStack {
            Spacer()
            ProgressView()
            Text("読み込み中...").font(.caption).foregroundColor(.gray)
            Spacer()
        }.padding()
    }

    private var toolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigationBarLeading) {
                Picker("ソート", selection: $viewModel.sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showClearConfirm = true }) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
            }
        }
    }
}

// 行の表示を別構造体にして型推論を助ける
struct ThreadRow: View {
    let thread: Thread
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(thread.title).font(.headline).lineLimit(2)
            HStack {
                Text("レス: \(thread.resCount)")
                Spacer()
                Text("勢い: \(Int(thread.ikioi))").foregroundColor(.orange)
            }.font(.caption)
        }
        .padding(.vertical, 4)
    }
}
