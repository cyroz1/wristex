import SwiftUI

@main
struct WristexApp: App {
    var body: some Scene {
        WindowGroup {
            if let route = ScreenshotMode.route {
                ScreenshotCaptureView(route: route)
            } else {
                MainTabView()
            }
        }
    }
}
