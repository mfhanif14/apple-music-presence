import SwiftUI

@main
struct MyApp: App {
    // Created at launch so presence starts without opening the menu.
    @ObservedObject private var controller = PresenceController.shared

    var body: some Scene {
        MenuBarExtra("Music Presence", systemImage: "music.note") {
            MenuContent(controller: controller)
        }
    }
}
