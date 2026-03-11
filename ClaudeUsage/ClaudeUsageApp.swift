import SwiftUI

@main
struct ClaudeUsageApp: App {
    var body: some Scene {
        MenuBarExtra("Claude Usage", systemImage: "chart.bar.fill") {
            ContentView()
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}
