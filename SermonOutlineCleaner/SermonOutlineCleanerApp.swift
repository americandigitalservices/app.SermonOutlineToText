import SwiftUI

//
//  SermonOutlineCleaner
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

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
