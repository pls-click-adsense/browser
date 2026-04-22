import SwiftUI

@main
struct MyBBSAppApp: App {
    var body: some Scene {
        WindowGroup {
            // 最初にスレ一覧画面を表示する
            ThreadListView()
        }
    }
}
