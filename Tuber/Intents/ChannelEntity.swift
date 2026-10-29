import AppIntents
import SwiftData

struct ChannelEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Channel"
    static let defaultQuery = ChannelQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ChannelQuery: EntityStringQuery {
    @MainActor
    private func all() -> [ChannelEntity] {
        let channels = (try? Persistence.container.mainContext.fetch(FetchDescriptor<Channel>(sortBy: [SortDescriptor(\.title)]))) ?? []
        return channels.map { ChannelEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ChannelEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ChannelEntity] {
        all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ChannelEntity] { all() }
}
