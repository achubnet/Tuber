import SwiftData
import SwiftUI

struct ChannelRef: Hashable {
    let id: String
    let title: String
    var avatarURL: URL?
}

struct ChannelsView: View {
    @Query(sort: \Channel.title) private var channels: [Channel]
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var global: [ChannelRef] = []

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let mine = q.isEmpty ? channels : channels.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let subscribed = Set(channels.map(\.id))

        NavigationStack {
            List {
                Section(q.isEmpty ? "" : String(localized: "My channels")) {
                    ForEach(mine) { c in
                        NavigationLink(value: ChannelRef(id: c.id, title: c.title, avatarURL: c.avatarURL)) {
                            HStack {
                                ChannelRow(title: c.title, avatarURL: c.avatarURL)
                                if c.hiddenFromFeed {
                                    Spacer()
                                    Image(systemName: "eye.slash").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        idx.map { mine[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                }
                let others = global.filter { !subscribed.contains($0.id) }
                if q.count >= 3, !others.isEmpty {
                    Section("Everywhere") {
                        ForEach(others, id: \.id) { ref in
                            NavigationLink(value: ref) {
                                HStack {
                                    ChannelRow(title: ref.title, avatarURL: ref.avatarURL)
                                    Spacer(minLength: 8)
                                    Button("Subscribe") {
                                        context.insert(Channel(id: ref.id, title: ref.title, avatarURL: ref.avatarURL))
                                        try? context.save()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search channels")
            .task(id: q) {
                global = []
                guard q.count >= 3 else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let results = try? await SearchService.search(q) else { return }
                global = results.compactMap {
                    if case let .channel(id, title, avatar) = $0 { ChannelRef(id: id, title: title, avatarURL: avatar) } else { nil }
                }
            }
            .overlay {
                if channels.isEmpty && q.isEmpty {
                    ContentUnavailableView {
                        Label("No channels yet", systemImage: "person.2")
                    } description: {
                        Text("Find channels in Search and subscribe, or import your YouTube subscriptions.")
                    } actions: {
                        NavigationLink("Import from YouTube") { SettingsView() }
                    }
                }
            }
            .navigationTitle("Channels")
            .toolbar {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
            }
            .navigationDestination(for: ChannelRef.self) { ChannelView(ref: $0) }
        }
    }
}

struct ChannelRow: View {
    let title: String
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary)
            }
            .frame(width: 40, height: 40).clipShape(Circle())
            Text(title).font(.body)
        }
    }
}

struct ChannelView: View {
    let ref: ChannelRef
    @Query private var videos: [Video]
    @Query private var channels: [Channel]
    @Environment(\.modelContext) private var context
    @State private var confirmMarkAll = false
    @State private var showHidden = false

    init(ref: ChannelRef) {
        self.ref = ref
        let id = ref.id
        _videos = Query(filter: #Predicate<Video> { $0.channelID == id }, sort: \Video.published, order: .reverse)
    }

    var body: some View {
        let subscribed = channels.first { $0.id == ref.id }
        let channel = Channel(id: ref.id, title: ref.title)
        List {
            ForEach(Self.visible(videos, showHidden: showHidden)) { video in
                VideoCard(video: video)
                    .videoActions(video)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
            }
            if FeedService.hasMore([channel]) {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                    .task(id: videos.count) { await FeedService.loadMore(channels: [channel], context: context) }
            }
        }
        .listStyle(.plain)
        .navigationTitle(ref.title)
        .toolbar {
            Menu {
                Button("Mark all as watched", systemImage: "checkmark.circle") { confirmMarkAll = true }
                Toggle("Show hidden videos", systemImage: "eye", isOn: $showHidden)
                if let subscribed {
                    Toggle("Hide from feed", systemImage: "eye.slash", isOn: Binding(
                        get: { subscribed.hiddenFromFeed },
                        set: { subscribed.hiddenFromFeed = $0; try? context.save() }))
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            Button(subscribed == nil ? "Subscribe" : "Subscribed") {
                if let subscribed { context.delete(subscribed) } else {
                    context.insert(Channel(id: ref.id, title: ref.title, avatarURL: ref.avatarURL))
                }
                try? context.save()
            }
            .buttonStyle(.borderedProminent)
            .tint(subscribed == nil ? .red : .gray)
        }
        .confirmationDialog("Mark all videos of this channel as watched?", isPresented: $confirmMarkAll, titleVisibility: .visible) {
            Button("Mark all as watched") { markAllWatched(subscribed) }
        }
        .task { await FeedService.refresh(channels: [Channel(id: ref.id, title: ref.title)], context: context) }
    }

    /// Hidden videos disappear here too, unless the user asks to see them again.
    static func visible(_ videos: [Video], showHidden: Bool) -> [Video] {
        showHidden ? videos : videos.filter { !$0.hidden }
    }

    private func markAllWatched(_ channel: Channel?) {
        let now = Date.now
        channel?.watchedBefore = now
        for video in videos where video.published <= now {
            video.watched = true
            video.watchLater = false
        }
        try? context.save()
    }
}
