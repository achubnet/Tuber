import SwiftData
import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                let channels = results.filter { if case .channel = $0 { true } else { false } }
                let videos = results.filter { if case .video = $0 { true } else { false } }
                if !channels.isEmpty {
                    Section("Channels") {
                        ForEach(channels) { r in
                            if case let .channel(id, title, avatar) = r {
                                NavigationLink(value: ChannelRef(id: id, title: title, avatarURL: avatar)) {
                                    HStack {
                                        ChannelRow(title: title, avatarURL: avatar)
                                        Spacer(minLength: 8)
                                        SubscribeButton(ref: ChannelRef(id: id, title: title, avatarURL: avatar))
                                    }
                                }
                            }
                        }
                    }
                }
                if !videos.isEmpty {
                    Section("Videos") {
                        ForEach(videos) { r in
                            if case let .video(id, title, _, channelTitle, duration) = r {
                                Button { Task { await PlayerModel.shared.play(videoID: id) } } label: {
                                    SearchVideoRow(id: id, title: title, channelTitle: channelTitle, duration: duration)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .overlay { if isSearching { ProgressView() } }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Channels, videos or a link")
            .onSubmit(of: .search) { Task { await search() } }
            .task(id: query) {
                let q = query.trimmingCharacters(in: .whitespaces)
                guard q.count >= 3, VideoLink.videoID(fromText: q) == nil else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await search()
            }
            .navigationDestination(for: ChannelRef.self) { ChannelView(ref: $0) }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if let id = VideoLink.videoID(fromText: q) {
            await PlayerModel.shared.play(videoID: id)
            return
        }
        isSearching = true
        results = (try? await SearchService.search(q)) ?? []
        isSearching = false
    }
}

struct SearchVideoRow: View {
    let id: String
    let title: String
    let channelTitle: String
    let duration: Double?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")) { $0.resizable().scaledToFill() }
                placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: 120, height: 68).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 4) {
                    Text(channelTitle)
                    if let duration { Text("· " + VideoCard.format(duration)) }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Inline subscribe toggle for a channel row.
struct SubscribeButton: View {
    let ref: ChannelRef
    @Query private var channels: [Channel]
    @Environment(\.modelContext) private var context

    var body: some View {
        let existing = channels.first { $0.id == ref.id }
        Button(existing == nil ? "Subscribe" : "Subscribed") {
            if let existing { context.delete(existing) } else {
                context.insert(Channel(id: ref.id, title: ref.title, avatarURL: ref.avatarURL))
            }
            try? context.save()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(existing == nil ? .red : .gray)
    }
}
