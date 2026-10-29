import Foundation
import SwiftData

struct ChannelFeed: Sendable {
    let channelID: String
    let title: String
    let entries: [FeedEntry]
}

enum FeedService {
    static func feed(channelID: String) async -> ChannelFeed? {
        let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsed = try RSSParser.parse(data)
            return ChannelFeed(channelID: channelID, title: parsed.channelTitle, entries: parsed.entries)
        } catch {
            return nil
        }
    }

    /// Pulls RSS for all channels in parallel and upserts videos, keeping user state.
    @MainActor
    static func refresh(channels: [Channel], context: ModelContext) async {
        let ids = channels.map(\.id)
        let feeds = await withTaskGroup(of: ChannelFeed?.self) { group in
            for id in ids { group.addTask { await feed(channelID: id) } }
            var all: [ChannelFeed] = []
            for await f in group { if let f { all.append(f) } }
            return all
        }
        for f in feeds {
            let shorts = Set(f.entries.filter(\.isShort).map(\.id))
            if !shorts.isEmpty,
               let stored = try? context.fetch(FetchDescriptor<Video>(predicate: #Predicate { shorts.contains($0.id) })) {
                stored.forEach(context.delete)
            }
            for e in f.entries where !e.isShort {
                _ = Video.upsert(id: e.id, channelID: f.channelID, channelTitle: f.title, title: e.title,
                                 published: e.published, in: context)
            }
        }
        try? context.save()
    }

    // MARK: Older videos

    @MainActor private static var tokens: [String: String] = [:]
    @MainActor private static var finished: Set<String> = []

    /// Loads the next page of each channel's Videos tab and stores videos not seen yet.
    @MainActor
    static func loadMore(channels: [Channel], context: ModelContext) async {
        let ids = channels.map(\.id).filter { !finished.contains($0) }
        let known = tokens
        let pages = await withTaskGroup(of: (String, ChannelPage?).self) { group in
            for id in ids {
                group.addTask { (id, try? await ChannelVideos.page(channelID: id, continuation: known[id])) }
            }
            var all: [(String, ChannelPage?)] = []
            for await p in group { all.append(p) }
            return all
        }
        for (id, page) in pages {
            guard let page else { continue }
            if let next = page.next { tokens[id] = next } else { finished.insert(id) }
            let title = channels.first { $0.id == id }?.title ?? ""
            let pageIDs = page.videos.map(\.id)
            let existing = Set(((try? context.fetch(FetchDescriptor<Video>(predicate: #Predicate { pageIDs.contains($0.id) }))) ?? []).map(\.id))
            for v in page.videos {
                // Keep exact RSS dates for videos we already have; only new ones get the approximate date.
                _ = Video.upsert(id: v.id, channelID: id, channelTitle: title, title: v.title,
                                 published: existing.contains(v.id) ? nil : v.published, duration: v.duration, in: context)
            }
        }
        try? context.save()
    }

    @MainActor static func hasMore(_ channels: [Channel]) -> Bool {
        channels.contains { !finished.contains($0.id) }
    }

    @MainActor static func isFinished(_ channelID: String) -> Bool { finished.contains(channelID) }

    /// The feed only shows videos newer than this date, so older pages always append at the bottom
    /// instead of slotting in between rows already on screen. It is the newest of the "oldest loaded"
    /// dates among channels that still have more to load.
    @MainActor static func cutoff(channels: [Channel], videos: [Video]) -> Date? {
        var oldest: [String: Date] = [:]
        for v in videos { oldest[v.channelID] = min(oldest[v.channelID] ?? v.published, v.published) }
        return channels.filter { !finished.contains($0.id) }.compactMap { oldest[$0.id] }.max()
    }
}
