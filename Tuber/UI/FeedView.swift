import AppIntents
import SwiftData
import SwiftUI

struct FeedView: View {
    @Query(sort: \Video.published, order: .reverse) private var videos: [Video]
    @Query private var channels: [Channel]
    @AppStorage("hideWatched") private var hideWatched = false
    @Environment(\.modelContext) private var context
    @State private var didRefresh = false
    @State private var loadingMore = false

    var body: some View {
        let shown = channels.filter { !$0.hiddenFromFeed }
        let subscribed = Set(shown.map(\.id))
        let later = videos.filter { $0.watchLater && !$0.hidden }
        let mine = videos.filter { subscribed.contains($0.channelID) }
        let cutoff = FeedService.cutoff(channels: shown, videos: mine)
        let feed = mine.filter { !$0.hidden && !(hideWatched && $0.watched) && $0.published >= (cutoff ?? .distantPast) }

        NavigationStack {
            List {
                if !later.isEmpty {
                    Section("Watch later") { rows(later) }
                }
                Section {
                    rows(feed)
                    if !shown.isEmpty, FeedService.hasMore(shown) {
                        ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                            .task(id: cutoff) { loadMore(before: cutoff, videos: mine) }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if channels.isEmpty {
                    ContentUnavailableView("No channels yet", systemImage: "person.2",
                                           description: Text("Find channels in Search and subscribe."))
                }
            }
            .navigationTitle("Feed")
            .toolbar {
                Menu {
                    Toggle("Hide watched", systemImage: "eye.slash", isOn: $hideWatched)
                } label: {
                    Image(systemName: hideWatched ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
            }
            .refreshable { await FeedService.refresh(channels: channels, context: context) }
            .task {
                guard !didRefresh else { return }
                didRefresh = true
                await FeedService.refresh(channels: channels, context: context)
            }
            .navigationDestination(for: ChannelRef.self) { ChannelView(ref: $0) }
            .onChange(of: channels.count, initial: true) { TuberShortcuts.updateAppShortcutParameters() }
        }
    }

    private func rows(_ list: [Video]) -> some View {
        ForEach(list) { video in
            VideoCard(video: video)
                .videoActions(video)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
    }

    /// Loads the next page only for channels that hold the cutoff back.
    private func loadMore(before cutoff: Date?, videos: [Video]) {
        guard !loadingMore else { return }
        var oldest: [String: Date] = [:]
        for v in videos { oldest[v.channelID] = min(oldest[v.channelID] ?? v.published, v.published) }
        let limiting = channels.filter { !$0.hiddenFromFeed }.filter {
            !FeedService.isFinished($0.id) && (cutoff == nil || (oldest[$0.id] ?? .distantFuture) >= cutoff!)
        }
        guard !limiting.isEmpty else { return }
        loadingMore = true
        Task {
            await FeedService.loadMore(channels: limiting, context: context)
            loadingMore = false
        }
    }
}
