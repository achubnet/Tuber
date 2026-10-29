import Foundation
import SwiftData

@Model
final class Channel {
    var id: String = ""
    var title: String = ""
    var avatarURL: URL?
    var subscribedAt: Date = Date.now
    /// "Mark all as watched": everything published up to this date counts as watched, including older videos loaded later.
    var watchedBefore: Date?
    /// Still subscribed, but its videos stay out of the main feed.
    var hiddenFromFeed: Bool = false

    init(id: String, title: String, avatarURL: URL? = nil) {
        self.id = id
        self.title = title
        self.avatarURL = avatarURL
    }
}
