import SwiftUI

struct PostView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BBSViewModel
    let threadId: String
    @State private var name = ""
    @State private var mail = ""
    @State private var bodyText = ""
    @State private var isSending = false
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("名前", text: $name)
                TextField("メール", text: $mail)
                TextEditor(text: $bodyText).frame(minHeight: 200)
            }
            .navigationTitle("書き込む")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("送信") {
                        isSending = true
                        Task {
                            if await viewModel.postReply(threadId: threadId, name: name, mail: mail, body: bodyText) {
                                dismiss()
                            }
                            isSending = false
                        }
                    }.disabled(bodyText.isEmpty || isSending)
                }
            }
        }
    }
}
