import Foundation
import SwiftData

@Model
final class Video {
    var id: String = ""
    var channelID: String = ""
    var channelTitle: String = ""
    var title: String = ""
    var published: Date = Date.now
    var duration: Double?
    var position: Double = 0
    var watched: Bool = false
    var watchLater: Bool = false
    var hidden: Bool = false
    var lastPlayedAt: Date?

    init(id: String, channelID: String, channelTitle: String, title: String, published: Date = .now, duration: Double? = nil) {
        self.id = id
        self.channelID = channelID
        self.channelTitle = channelTitle
        self.title = title
        self.published = published
        self.duration = duration
    }

    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
    /// 16:9 thumbnails: HD first, small one for old videos without HD.
    var wideThumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hq720.jpg") }
    var smallThumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
    var shareURL: URL { URL(string: "https://youtu.be/\(id)")! }
    var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(position / duration, 1)
    }
}

extension Video {
    /// Finds a video by ID or inserts a new one.
    @MainActor
    static func upsert(id: String, channelID: String, channelTitle: String, title: String,
                       published: Date? = nil, duration: Double? = nil, in context: ModelContext) -> Video {
        let descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.title = title
            if !channelTitle.isEmpty { existing.channelTitle = channelTitle }
            if !channelID.isEmpty { existing.channelID = channelID }
            if let published { existing.published = published }
            if let duration { existing.duration = duration }
            return existing
        }
        let video = Video(id: id, channelID: channelID, channelTitle: channelTitle, title: title,
                          published: published ?? .now, duration: duration)
        context.insert(video)
        let channels = FetchDescriptor<Channel>(predicate: #Predicate { $0.id == channelID })
        if let cutoff = (try? context.fetch(channels).first)?.watchedBefore, video.published <= cutoff {
            video.watched = true
        }
        return video
    }
}
