import SwiftUI

struct ThreadListView: View {
    @StateObject var viewModel = BBSViewModel()
    @State private var isShowingBrowser = false
    @State private var isShowingClearAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("🛠 設定・認証") {
                    Button(action: { isShowingBrowser = true }) {
                        Label("独立認証ブラウザを開く", systemImage: "safari.fill").bold()
                    }
                    Button(role: .destructive, action: { isShowingClearAlert = true }) {
                        Label("キャッシュ・Cookie削除", systemImage: "trash")
                    }
                }
                Section("📜 スレッド一覧") {
                    ForEach(viewModel.threads) { t in
                        NavigationLink(destination: ThreadDetailView(viewModel: viewModel, thread: t)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.title).font(.subheadline).fontWeight(.medium).lineLimit(2)
                                HStack {
                                    Label("\(t.resCount)", systemImage: "bubble.right").foregroundColor(.secondary)
                                    Label("\(Int(t.ikioi))", systemImage: "bolt.fill").foregroundColor(t.ikioi > 500 ? .red : .orange)
                                    Spacer()
                                    Text(Date(timeIntervalSince1970: t.createdAt), style: .time).foregroundColor(.secondary)
                                }.font(.caption2)
                            }.padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("liveedge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("ソート", selection: $viewModel.sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .alert("削除確認", isPresented: $isShowingClearAlert) {
                Button("削除", role: .destructive) { Task { await viewModel.clearWebData() } }
                Button("キャンセル", role: .cancel) {}
            } message: { Text("認証情報をリセットしますか？") }
            .sheet(isPresented: $isShowingBrowser) {
                NavigationStack {
                    WebView(url: URL(string: AppConfig.boardURL)!)
                        .navigationTitle("認証用ブラウザ").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { isShowingBrowser = false } } }
                }
            }
            .refreshable { await viewModel.fetchThreadList() }
            .onAppear { if viewModel.threads.isEmpty { Task { await viewModel.fetchThreadList() } } }
        }
    }
}
