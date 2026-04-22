import SwiftUI

struct PostView: View {
    @ObservedObject var viewModel: BBSViewModel
    let threadId: String
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var mail = ""
    @State private var bodyText = ""
    @State private var isSending = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("名前 / メール")) {
                    TextField("名前", text: $name)
                    TextField("メール", text: $mail)
                }
                Section(header: Text("本文")) {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("書き込み")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("送信") {
                        isSending = true
                        Task {
                            let success = await viewModel.postReply(threadId: threadId, name: name, mail: mail, body: bodyText)
                            isSending = false
                            if success {
                                dismiss()
                            }
                        }
                    }
                    .disabled(bodyText.isEmpty || isSending)
                }
            }
            .overlay {
                if isSending {
                    ProgressView("送信中...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                }
            }
        }
    }
}
