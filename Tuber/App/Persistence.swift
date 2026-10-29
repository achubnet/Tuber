import Foundation
import SwiftData

enum Persistence {
    static let cloudContainer = Bundle.main.object(forInfoDictionaryKey: "TuberCloudContainer") as? String ?? ""

    /// Synced to the owner's private iCloud; falls back to a local store if CloudKit is unavailable.
    @MainActor static let container: ModelContainer = {
        let schema = Schema([Channel.self, Video.self])
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainer))
        do { return try ModelContainer(for: schema, configurations: cloud) }
        catch { print("Persistence: iCloud unavailable, using local store: \(error)") }
        do { return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)) }
        catch { fatalError("SwiftData: \(error)") }
    }()

    /// iCloud sync can't enforce unique IDs, so merge duplicates that arrive from other devices.
    @MainActor static func dedupe() {
        let context = container.mainContext
        var seenChannels = Set<String>()
        for c in (try? context.fetch(FetchDescriptor<Channel>(sortBy: [SortDescriptor(\.subscribedAt)]))) ?? [] {
            if !seenChannels.insert(c.id).inserted { context.delete(c) }
        }
        var keep: [String: Video] = [:]
        for v in (try? context.fetch(FetchDescriptor<Video>())) ?? [] {
            guard let other = keep[v.id] else { keep[v.id] = v; continue }
            other.position = max(other.position, v.position)
            other.watched = other.watched || v.watched
            other.watchLater = other.watchLater || v.watchLater
            other.lastPlayedAt = [other.lastPlayedAt, v.lastPlayedAt].compactMap { $0 }.max()
            if other.duration == nil { other.duration = v.duration }
            context.delete(v)
        }
        try? context.save()
    }
}
