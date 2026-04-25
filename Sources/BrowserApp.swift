import SwiftUI
import UIKit
@main
struct BrowserApp: App {
    init() {
        // ウィンドウの背景色をsystemBackgroundに設定
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.backgroundColor = .systemBackground }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
