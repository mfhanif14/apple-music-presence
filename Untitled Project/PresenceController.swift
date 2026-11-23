import AppKit
import Combine
import Foundation

/// What Discord shows in the short status line under your name.
enum StatusDisplay: Int, CaseIterable, Identifiable {
    case appName = 0   // "Listening to Apple Music"
    case artist = 1    // "Listening to DECO*27"
    case track = 2     // "Listening to アンドロイドガール"

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .appName: return "App name"
        case .artist: return "Artist"
        case .track: return "Track"
        }
    }
}

struct NowPlaying: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
}

final class PresenceController: ObservableObject {
    static let shared = PresenceController()
    static let clientID = "1574222767073665237"

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var discordConnected = false

    private let discord = DiscordIPC(clientID: PresenceController.clientID)
    private let artwork = ArtworkFinder()
    private var lastKey: String?
    private var lastStart: Double = 0
    private var hasActivity = false

    private init() {
        Task {
            while true {
                await self.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func tick() async {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "presenceEnabled") as? Bool ?? true
        let rawDisplay = defaults.object(forKey: "statusDisplay") as? Int ?? StatusDisplay.track.rawValue
        let display = StatusDisplay(rawValue: rawDisplay) ?? .track
        let showButton = defaults.object(forKey: "showButton") as? Bool ?? true

        let current = MusicReader.read()
        if current != nowPlaying { nowPlaying = current }

        guard enabled, let track = current, track.isPlaying else {
            clearPresence()
            return
        }

        if !discord.isConnected, discord.connect() {
            lastKey = nil
        }
        setConnected(discord.isConnected)
        guard discord.isConnected else { return }

        // Only send when the track/setting changes or the user seeks (Discord rate-limits updates).
        let start = Date().timeIntervalSince1970 - track.position
        let key = "\(track.id)|\(display.rawValue)|\(showButton)"
        if key == lastKey, abs(start - lastStart) < 3 { return }

        let links = await artwork.links(artist: track.artist, title: track.title, album: track.album)
        let activity = Self.makeActivity(
            track: track,
            start: start,
            links: links,
            display: display,
            showButton: showButton
        )

        if discord.setActivity(activity) {
            lastKey = key
            lastStart = start
            hasActivity = true
        } else {
            lastKey = nil
        }
        setConnected(discord.isConnected)
    }

    private func clearPresence() {
        if hasActivity, discord.isConnected {
            _ = discord.setActivity(nil)
        }
        hasActivity = false
        lastKey = nil
        setConnected(discord.isConnected)
    }

    private func setConnected(_ value: Bool) {
        if discordConnected != value { discordConnected = value }
    }

    private static func makeActivity(
        track: NowPlaying,
        start: Double,
        links: TrackLinks,
        display: StatusDisplay,
        showButton: Bool
    ) -> [String: Any] {
        var timestamps: [String: Any] = ["start": Int((start * 1000).rounded())]
        if track.duration > 0 {
            timestamps["end"] = Int(((start + track.duration) * 1000).rounded())
        }

        var activity: [String: Any] = [
            "type": 2, // Listening
            "status_display_type": display.rawValue,
            "details": text(track.title),
            "state": text(track.artist),
            "timestamps": timestamps,
        ]

        // Only the large image (album cover). No small_image, so no Apple Music badge.
        if let imageURL = links.artworkURL {
            var assets: [String: Any] = ["large_image": imageURL]
            if !track.album.isEmpty { assets["large_text"] = text(track.album) }
            activity["assets"] = assets
        }

        // Buttons are only visible to other people, not on your own profile.
        if showButton, let songURL = links.songURL {
            activity["buttons"] = [["label": "Play on Apple Music", "url": songURL]]
        }
        return activity
    }

    /// Discord requires 2...128 characters.
    private static func text(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > 128 { result = String(result.prefix(127)) + "…" }
        while result.count < 2 { result += " " }
        return result
    }
}
