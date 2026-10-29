import Foundation

struct PageVideo: Sendable {
    let id: String
    let title: String
    let duration: Double?
    let published: Date
}

struct ChannelPage: Sendable {
    let videos: [PageVideo]
    let next: String?
}

/// Pages through a channel's Videos tab (no Shorts) via InnerTube browse.
enum ChannelVideos {
    static func page(channelID: String, continuation: String?) async throws -> ChannelPage {
        let body: [String: Any] = continuation.map { ["continuation": $0] }
            ?? ["browseId": channelID, "params": "EgZ2aWRlb3PyBgQKAjoA"]
        let json = try await InnerTube.post("browse", body: body, language: "en")
        return parse(json, now: .now)
    }

    static func parse(_ json: [String: Any], now: Date) -> ChannelPage {
        var videos: [PageVideo] = []
        var next: String?
        // The grid is the array that holds richItemRenderers; its trailing item carries the next-page token.
        func walk(_ o: Any) {
            if let array = o as? [Any] {
                let items = array.compactMap { $0 as? [String: Any] }
                if items.contains(where: { $0["richItemRenderer"] != nil }) {
                    for item in items {
                        if let lockup = InnerTube.find("lockupViewModel", in: item).first, let v = video(lockup, now: now) {
                            videos.append(v)
                        }
                        if let cont = item["continuationItemRenderer"],
                           let token = InnerTube.find("continuationCommand", in: cont).first?["token"] as? String {
                            next = token
                        }
                    }
                    return
                }
                array.forEach(walk)
            } else if let dict = o as? [String: Any] {
                dict.values.forEach(walk)
            }
        }
        walk(json)
        return ChannelPage(videos: videos, next: next)
    }

    private static func video(_ lockup: [String: Any], now: Date) -> PageVideo? {
        guard let id = lockup["contentId"] as? String,
              (lockup["contentType"] as? String) == "LOCKUP_CONTENT_TYPE_VIDEO",
              let meta = (lockup["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any] else { return nil }
        let title = (meta["title"] as? [String: Any])?["content"] as? String ?? ""
        let parts = InnerTube.find("text", in: meta["metadata"] ?? [:]).compactMap { $0["content"] as? String }
        let published = parts.lazy.compactMap { relativeDate($0, now: now) }.first ?? now
        let badges = InnerTube.find("thumbnailBadgeViewModel", in: lockup["contentImage"] ?? [:]).compactMap { $0["text"] as? String }
        let duration = badges.lazy.compactMap { SearchService.parseDuration($0) }.first
        return PageVideo(id: id, title: title, duration: duration, published: published)
    }

    /// "5 days ago" -> now - 5 days. Approximate: month = 30 days, year = 365 days.
    static func relativeDate(_ text: String, now: Date) -> Date? {
        let words = text.lowercased().split(separator: " ")
        guard words.last == "ago", words.count >= 3,
              let n = Double(words[words.count - 3]) else { return nil }
        let unit = words[words.count - 2]
        let seconds: Double
        switch unit.hasSuffix("s") ? String(unit.dropLast()) : String(unit) {
        case "second": seconds = 1
        case "minute": seconds = 60
        case "hour": seconds = 3600
        case "day": seconds = 86_400
        case "week": seconds = 7 * 86_400
        case "month": seconds = 30 * 86_400
        case "year": seconds = 365 * 86_400
        default: return nil
        }
        return now - n * seconds
    }
}
