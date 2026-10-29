import AppIntents
import SwiftData

struct ResumeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Continue watching"

    @MainActor
    func perform() async throws -> some IntentResult {
        var d = FetchDescriptor<Video>(predicate: #Predicate { $0.lastPlayedAt != nil },
                                       sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        d.fetchLimit = 1
        if let video = try? Persistence.container.mainContext.fetch(d).first {
            await PlayerModel.shared.play(videoID: video.id, present: false)
        }
        return .result()
    }
}

struct LatestFromChannelIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play latest video"

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let latest = await IntentHelpers.latest(channelID: channel.id, title: channel.title, count: 1).first {
            await PlayerModel.shared.play(videoID: latest.id, present: false)
        }
        return .result()
    }
}

struct WhatsNewIntent: AppIntent {
    static let title: LocalizedStringResource = "What's new on a channel"

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let videos = await IntentHelpers.latest(channelID: channel.id, title: channel.title, count: 3)
        guard !videos.isEmpty else { return .result(dialog: "No new videos on \(channel.title).") }
        let titles = videos.map(\.title).joined(separator: ". ")
        return .result(dialog: "Latest on \(channel.title): \(titles)")
    }
}

@MainActor
enum IntentHelpers {
    static func latest(channelID: String, title: String, count: Int) async -> [Video] {
        let context = Persistence.container.mainContext
        await FeedService.refresh(channels: [Channel(id: channelID, title: title)], context: context)
        var d = FetchDescriptor<Video>(predicate: #Predicate { $0.channelID == channelID },
                                       sortBy: [SortDescriptor(\.published, order: .reverse)])
        d.fetchLimit = count
        return (try? context.fetch(d)) ?? []
    }
}

struct TuberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ResumeIntent(), phrases: [
            "Continue in \(.applicationName)",
            "Resume \(.applicationName)",
        ], shortTitle: "Continue watching", systemImageName: "play.fill")
        AppShortcut(intent: LatestFromChannelIntent(), phrases: [
            "Play latest from \(\.$channel) in \(.applicationName)",
            "Latest video from \(\.$channel) in \(.applicationName)",
        ], shortTitle: "Latest from channel", systemImageName: "play.rectangle")
        AppShortcut(intent: WhatsNewIntent(), phrases: [
            "What's new on \(\.$channel) in \(.applicationName)",
        ], shortTitle: "What's new", systemImageName: "sparkles")
    }
}
