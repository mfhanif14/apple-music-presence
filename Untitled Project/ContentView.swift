import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var controller: PresenceController
    @AppStorage("presenceEnabled") private var enabled = true
    @AppStorage("statusDisplay") private var statusDisplay = StatusDisplay.track.rawValue
    @AppStorage("showButton") private var showButton = true
    @AppStorage("showCredit") private var showCredit = true

    var body: some View {
        if let track = controller.nowPlaying {
            Text(track.isPlaying ? track.title : "\(track.title) (paused)")
            Text(track.artist)
        } else {
            Text("Nothing playing")
        }
        Text(controller.discordConnected ? "Discord: connected" : "Discord: not connected")

        Divider()

        Toggle("Show presence", isOn: $enabled)
        Toggle("Show Apple Music button", isOn: $showButton)
        Toggle("Show credit button", isOn: $showCredit)
        Picker("Status shows", selection: $statusDisplay) {
            ForEach(StatusDisplay.allCases) { option in
                Text(option.label).tag(option.rawValue)
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
