import SwiftUI

struct ThreadListView: View {
    @StateObject var viewModel = BBSViewModel()
    @State private var showClearConfirm = false
    
    var body: some View {
        NavigationView {
            ZStack {
                List {
                    ForEach(viewModel.threads) { thread in
                        NavigationLink(destination: ThreadDetailView(thread: thread, viewModel: viewModel)) {
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
                        .onAppear {
                            // リストの末尾付近に来たら追加読み込みを試みる
                            Task { await viewModel.loadMoreThreadsIfNeeded(currentThread: thread) }
                        }
                    }
                    
                    // 下端に到達した時のインジケーター（上に引っ張る演出用）
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("読み込み中...").font(.caption).foregroundColor(.gray)
                            Spacer()
                        }.padding()
                    }
                }
                .refreshable { await viewModel.fetchThreadList() } // 下に引っ張って更新
                
                if viewModel.isFetching && viewModel.threads.isEmpty {
                    ProgressView("読み込み中...")
                }
            }
            .navigationTitle("ニュース速報(VIP)")
            .toolbar {
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
        // クッキー削除の確認（ワンクッション）
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
}
