import Foundation

enum SponsorBlock {
    /// Segments to skip; any error (including 404 "no segments") means none.
    static func segments(videoID: String, categories: [String]) async -> [Segment] {
        var c = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")!
        let cats = "[" + categories.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        c.queryItems = [URLQueryItem(name: "videoID", value: videoID), URLQueryItem(name: "categories", value: cats)]
        guard let url = c.url,
              let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode([Segment].self, from: result.0)) ?? []
    }
}
