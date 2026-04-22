import SwiftUI

struct PostView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BBSViewModel
    let threadId: String
    @State private var name = ""
    @State private var mail = ""
    @State private var bodyText = ""
    @State private var resultMessage: String? = nil
    @State private var isShowingError = false
    @State private var isSending = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("名前 / メール") { TextField("名前", text: $name); TextField("メール", text: $mail) }
                Section("本文") { TextEditor(text: $bodyText).frame(minHeight: 150) }
            }
            .navigationTitle("レスを書く").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSending { ProgressView() } else {
                        Button("書き込む") {
                            Task {
                                isSending = true
                                let res = await viewModel.postReply(threadId: threadId, name: name, mail: mail, body: bodyText)
                                isSending = false
                                if res.isSuccess {
                                    name = ""; mail = ""; bodyText = ""
                                    dismiss()
                                } else {
                                    resultMessage = res.message
                                    isShowingError = true
                                }
                            }
                        }.disabled(bodyText.isEmpty)
                    }
                }
            }
            .alert("エラー", isPresented: $isShowingError) { Button("OK"){} } message: { Text(resultMessage ?? "") }
        }
    }
}
