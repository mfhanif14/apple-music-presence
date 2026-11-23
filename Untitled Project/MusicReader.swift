import AppKit
import Foundation

/// Reads the current track from the Music app via AppleScript.
enum MusicReader {
    private static let script = NSAppleScript(source: """
    if application "Music" is running then
        tell application "Music"
            try
                if player state is stopped then return {}
                set t to current track
                set pid to ""
                try
                    set pid to persistent ID of t
                end try
                return {pid, name of t, artist of t, album of t, duration of t, player position, (player state is playing)}
            end try
        end tell
    end if
    return {}
    """)

    static func read() -> NowPlaying? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return nil
        }
        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error), result.numberOfItems >= 7 else {
            return nil
        }

        func string(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        func number(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }

        let title = string(2)
        let artist = string(3)
        guard !title.isEmpty else { return nil }

        let persistentID = string(1)
        return NowPlaying(
            id: persistentID.isEmpty ? "\(title)|\(artist)" : persistentID,
            title: title,
            artist: artist,
            album: string(4),
            duration: number(5),
            position: number(6),
            isPlaying: result.atIndex(7)?.booleanValue ?? false
        )
    }
}
