import SwiftUI

//
//  SermonOutlineCleaner
//  Copyright (C) 2026 Daniel Horning
//  Licensed under the GNU General Public License v3.0 (GPL-3.0)
//

@main
struct SermonOutlineCleanerApp: App {
    @State private var viewModel = SermonWorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Divider()
                Button {
                    viewModel.resetAppleEventsPermission(showConfirmationAlert: true)
                } label: {
                    Label("Reset Permissions", systemImage: "gearshape.arrow.triangle.2.circlepath")
                }
            }
        }
    }
}
