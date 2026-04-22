import SwiftUI

struct PostView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BBSViewModel
    let threadId: String
    @State private var name = ""
    @State private var mail = ""
    @State private var bodyText = ""
    @State private var isSending = false
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("名前 / メール") {
                    TextField("名前", text: $name)
                    TextField("メール", text: $mail)
                }
                Section("本文") {
                    TextEditor(text: $bodyText).frame(minHeight: 200)
                }
            }
            .navigationTitle("書き込む")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("送信") {
                            isSending = true
                            Task {
                                let success = await viewModel.postReply(threadId: threadId, name: name, mail: mail, body: bodyText)
                                if success {
                                    dismiss()
                                    // 閉じた後に親画面を更新
                                    await viewModel.fetchPosts(datId: threadId)
                                } else {
                                    showError = true
                                }
                                isSending = false
                            }
                        }.disabled(bodyText.isEmpty)
                    }
                }
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text("書き込みに失敗しました。")
            }
        }
    }
}
