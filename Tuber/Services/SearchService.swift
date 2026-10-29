import Foundation

enum SearchResult: Identifiable, Hashable {
    case channel(id: String, title: String, avatarURL: URL?)
    case video(id: String, title: String, channelID: String, channelTitle: String, duration: Double?)

    var id: String {
        switch self {
        case .channel(let id, _, _): "c" + id
        case .video(let id, _, _, _, _): "v" + id
        }
    }
}

enum SearchService {
    static func search(_ query: String) async throws -> [SearchResult] {
        let json = try await InnerTube.post("search", body: ["query": query])
        let channels = InnerTube.find("channelRenderer", in: json).compactMap { r -> SearchResult? in
            guard let id = r["channelId"] as? String else { return nil }
            let thumbs = (r["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let avatar = (thumbs?.last?["url"] as? String).flatMap { URL(string: $0.hasPrefix("//") ? "https:" + $0 : $0) }
            return .channel(id: id, title: InnerTube.text(r["title"]), avatarURL: avatar)
        }
        let videos = InnerTube.find("videoRenderer", in: json).compactMap { r -> SearchResult? in
            guard let id = r["videoId"] as? String else { return nil }
            let nav = r["navigationEndpoint"] as? [String: Any]
            let url = ((nav?["commandMetadata"] as? [String: Any])?["webCommandMetadata"] as? [String: Any])?["url"] as? String
            if url?.contains("/shorts/") == true || nav?["reelWatchEndpoint"] != nil { return nil }
            let owner = ((r["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]])?.first
            let channelID = ((owner?["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
            return .video(id: id, title: InnerTube.text(r["title"]), channelID: channelID ?? "",
                          channelTitle: owner?["text"] as? String ?? "",
                          duration: parseDuration(InnerTube.text(r["lengthText"])))
        }
        return channels + videos
    }

    /// "1:02:03" -> 3723
    static func parseDuration(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
