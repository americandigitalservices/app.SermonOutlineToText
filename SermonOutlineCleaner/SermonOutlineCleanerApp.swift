import SwiftUI

extension Notification.Name {
    static let resetAppPermissions = Notification.Name("resetAppPermissions")
}

@main
struct SermonOutlineCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Divider()
                Button {
                    NotificationCenter.default.post(name: .resetAppPermissions, object: nil)
                } label: {
                    Label("Reset Permissions", systemImage: "gearshape.arrow.triangle.2.circlepath")
                }
            }
        }
    }
}
