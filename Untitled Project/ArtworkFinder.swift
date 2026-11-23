import Foundation

struct TrackLinks: Equatable {
    var artworkURL: String?
    var songURL: String?
}

/// Finds the album cover and Apple Music link with the public iTunes Search API
/// (Discord needs an image URL, not a file).
final class ArtworkFinder {
    private var cache: [String: TrackLinks] = [:]

    func links(artist: String, title: String, album: String) async -> TrackLinks {
        let key = "\(artist)|\(title)|\(album)"
        if let cached = cache[key] { return cached }

        if let found = await search(term: "\(artist) \(title)", title: title, album: album) {
            cache[key] = found
            return found
        }
        return TrackLinks() // request failed; try again next time
    }

    /// nil = request failed.
    private func search(term: String, title: String, album: String) async -> TrackLinks? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier.lowercased() ?? "us"),
        ]
        guard let url = components.url,
              let result = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(SearchResponse.self, from: result.0)
        else { return nil }

        func normalize(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }
        let results = response.results
        let sameTitle = results.filter { normalize($0.trackName ?? "") == normalize(title) }
        let pick = sameTitle.first { normalize($0.collectionName ?? "") == normalize(album) }
            ?? sameTitle.first
            ?? results.first { normalize($0.collectionName ?? "") == normalize(album) }
            ?? results.first

        // Only link the song when the title really matches, so the button never opens a wrong song.
        let songURL = (pick.map { normalize($0.trackName ?? "") == normalize(title) } ?? false) ? pick?.trackViewUrl : nil

        return TrackLinks(
            artworkURL: pick?.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
            songURL: songURL
        )
    }
}

nonisolated private struct SearchResponse: Decodable {
    let results: [SearchItem]
}

nonisolated private struct SearchItem: Decodable {
    let trackName: String?
    let collectionName: String?
    let artworkUrl100: String?
    let trackViewUrl: String?
}
